package jscissors;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.lang.management.ManagementFactory;
import java.net.ProtocolFamily;
import java.net.SocketAddress;
import java.net.StandardProtocolFamily;
import java.nio.ByteBuffer;
import java.nio.channels.SocketChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import javax.management.MBeanServerConnection;
import javax.management.ObjectName;
import javax.management.remote.JMXConnector;
import javax.management.remote.JMXConnectorFactory;
import javax.management.remote.JMXServiceURL;

/**
 * Loads the agent in a running JVM of the same container, without jcmd (the cp images ship a JRE without it, nor the
 * jdk.attach module) and without restart:
 *
 * <pre>
 * java -cp jscissors.jar jscissors.Attach [--pid &lt;pid&gt;|auto] [--jmx &lt;host:port&gt;] --agent-args &lt;args&gt;
 * </pre>
 *
 * 1. the HotSpot attach protocol (what jcmd does): .attach_pid file + SIGQUIT, then a "load instrument" request on the
 *    /tmp/.java_pid&lt;pid&gt; unix socket. Needs JDK 16+ (unix domain sockets) to run this class, the same user as the
 *    target JVM, and no -XX:+DisableAttachMechanism.
 * 2. otherwise, with --jmx: the JVMTI.agent_load diagnostic command over JMX (JDK 9+ target).
 *
 * Exit code 0 when the agent is loaded.
 */
public final class Attach {
    private Attach() {
    }

    public static void main(String[] argv) throws Exception {
        String pid = "auto";
        String jmx = null;
        String agentArgs = "";
        for (int i = 0; i < argv.length - 1; i++) {
            switch (argv[i]) {
                case "--pid": pid = argv[++i]; break;
                case "--jmx": jmx = argv[++i]; break;
                case "--agent-args": agentArgs = argv[++i]; break;
                default: break;
            }
        }
        String jar = new File(Attach.class.getProtectionDomain().getCodeSource().getLocation().toURI()).getAbsolutePath();
        if ("auto".equals(pid)) {
            pid = findJvm();
        }
        String socketError = null;
        if (pid != null) {
            try {
                System.out.println("attaching to pid " + pid + " (" + command(pid) + ") with the attach protocol");
                attachWithSocket(pid, jar, agentArgs);
                System.out.println("agent loaded in pid " + pid);
                return;
            } catch (Throwable t) {
                socketError = t.toString();
                System.out.println("attach protocol failed: " + socketError);
            }
        } else {
            System.out.println("no other java process found in /proc");
        }
        if (jmx != null) {
            try {
                System.out.println("loading the agent over JMX (" + jmx + ")");
                attachWithJmx(jmx, jar, agentArgs);
                System.out.println("agent loaded over JMX");
                return;
            } catch (Throwable t) {
                System.out.println("JMX failed: " + t);
            }
        }
        System.exit(1);
    }

    /** the java process of the container: the oldest one, other than this one */
    static String findJvm() throws IOException {
        String self = ManagementFactory.getRuntimeMXBean().getName().split("@")[0];
        List<Long> pids = new ArrayList<>();
        File[] entries = new File("/proc").listFiles();
        if (entries == null) {
            return null;
        }
        for (File entry : entries) {
            String name = entry.getName();
            if (!name.matches("\\d+") || name.equals(self)) {
                continue;
            }
            String cmd = command(name);
            String exe = cmd.split(" ")[0];
            if ((exe.endsWith("/java") || exe.equals("java")) && !cmd.contains("jscissors.Attach")) {
                pids.add(Long.parseLong(name));
            }
        }
        if (pids.isEmpty()) {
            return null;
        }
        java.util.Collections.sort(pids);
        if (pids.size() > 1) {
            System.out.println("java processes: " + pids + ", using the oldest one (--pid to choose)");
        }
        return String.valueOf(pids.get(0));
    }

    static String command(String pid) {
        try {
            String cmd = new String(Files.readAllBytes(new File("/proc/" + pid + "/cmdline").toPath()), StandardCharsets.UTF_8).replace('\0', ' ').trim();
            // the main class, not the whole command line (it can hold secrets)
            String main = "";
            String[] parts = cmd.split(" ");
            for (int i = 1; i < parts.length; i++) {
                if (parts[i].equals("-cp") || parts[i].equals("-classpath") || parts[i].equals("--class-path")) {
                    i++;
                } else if (!parts[i].startsWith("-")) {
                    main = parts[i];
                    break;
                }
            }
            return parts[0] + (main.isEmpty() ? "" : " " + main);
        } catch (IOException e) {
            return "";
        }
    }

    static void attachWithSocket(String pid, String jar, String agentArgs) throws Exception {
        String tmp = new File("/proc/" + pid + "/root/tmp").canRead() ? "/proc/" + pid + "/root/tmp" : "/tmp";
        File socket = new File(tmp, ".java_pid" + pid);
        if (!socket.exists()) {
            // asks the JVM to start its attach listener
            File trigger = new File("/proc/" + pid + "/cwd", ".attach_pid" + pid);
            try {
                trigger.createNewFile();
            } catch (IOException e) {
                trigger = new File(tmp, ".attach_pid" + pid);
                trigger.createNewFile();
            }
            try {
                Process kill = new ProcessBuilder("kill", "-QUIT", pid).inheritIO().start();
                if (kill.waitFor() != 0) {
                    throw new IOException("kill -QUIT " + pid + " failed");
                }
                for (int i = 0; i < 100 && !socket.exists(); i++) {
                    Thread.sleep(100);
                }
            } finally {
                trigger.delete();
            }
            if (!socket.exists()) {
                throw new IOException("the JVM did not open " + socket + " (-XX:+DisableAttachMechanism, or another user)");
            }
        }
        // unix domain sockets: JDK 16+, through reflection so that the agent itself still compiles for JDK 8
        Class<?> addressClass = Class.forName("java.net.UnixDomainSocketAddress");
        SocketAddress address = (SocketAddress) addressClass.getMethod("of", String.class).invoke(null, socket.getAbsolutePath());
        ProtocolFamily unix = StandardProtocolFamily.valueOf("UNIX");
        try (SocketChannel channel = (SocketChannel) SocketChannel.class.getMethod("open", ProtocolFamily.class).invoke(null, unix)) {
            channel.connect(address);
            // protocol 1: <version> <command> <3 arguments>, each null terminated
            String request = "1\0load\0instrument\0false\0" + jar + (agentArgs.isEmpty() ? "" : "=" + agentArgs) + "\0";
            channel.write(ByteBuffer.wrap(request.getBytes(StandardCharsets.UTF_8)));
            ByteArrayOutputStream response = new ByteArrayOutputStream();
            ByteBuffer buffer = ByteBuffer.allocate(4096);
            while (channel.read(buffer) > 0) {
                response.write(buffer.array(), 0, buffer.position());
                buffer.clear();
            }
            String text = response.toString("UTF-8").trim();
            String[] lines = text.split("\n");
            // "0" then, for the instrument library, "return code: 0" (JDK 9+) or "0" (JDK 8)
            boolean ok = lines.length > 0 && lines[0].trim().equals("0")
                    && (lines.length == 1 || lines[lines.length - 1].trim().matches("(return code: )?0"));
            if (!ok) {
                throw new IOException("the JVM refused to load the agent: " + text.replace('\n', ' '));
            }
        }
    }

    static void attachWithJmx(String hostPort, String jar, String agentArgs) throws Exception {
        JMXServiceURL url = new JMXServiceURL("service:jmx:rmi:///jndi/rmi://" + hostPort + "/jmxrmi");
        try (JMXConnector connector = JMXConnectorFactory.connect(url)) {
            MBeanServerConnection mbeans = connector.getMBeanServerConnection();
            // JVMTI.agent_load <library> [<options>]: a .jar is loaded as a java agent. Quoted, or the parser of the
            // diagnostic commands takes config=... for one of its own key=value options
            String[] dcmdArgs = agentArgs.isEmpty() ? new String[]{jar} : new String[]{jar, "\"" + agentArgs + "\""};
            Object result = mbeans.invoke(new ObjectName("com.sun.management:type=DiagnosticCommand"), "jvmtiAgentLoad",
                    new Object[]{dcmdArgs}, new String[]{String[].class.getName()});
            String text = String.valueOf(result).trim();
            if (!text.isEmpty() && !text.equals("null")) {
                System.out.println(text);
                if (text.toLowerCase().contains("fail") || text.toLowerCase().contains("error")) {
                    throw new IOException(text);
                }
            }
        }
    }
}
