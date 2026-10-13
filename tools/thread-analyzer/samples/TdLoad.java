import java.io.*;
import java.net.*;
import java.util.concurrent.*;

/** Thread dump scenarios: deadlock, lock contention, CPU-hot thread, thread stuck on a socket read, leaking pool */
public class TdLoad {
    static final Object LOCK_A = new Object(), LOCK_B = new Object(), SHARED = new Object();

    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { } }

    public static void main(String[] args) throws Exception {
        // deadlock
        new Thread(() -> { synchronized (LOCK_A) { sleep(200); synchronized (LOCK_B) { } } }, "deadlock-1").start();
        new Thread(() -> { synchronized (LOCK_B) { sleep(200); synchronized (LOCK_A) { } } }, "deadlock-2").start();
        // contention: one holder sleeping inside the monitor, 8 blocked workers
        new Thread(() -> { synchronized (SHARED) { sleep(Long.MAX_VALUE); } }, "lock-holder").start();
        sleep(100);
        for (int i = 0; i < 8; i++) new Thread(() -> { synchronized (SHARED) { } }, "worker-" + i).start();
        // CPU-hot thread
        new Thread(() -> { long x = 0; while (true) { x += System.nanoTime() % 7; } }, "cpu-burner").start();
        // Connect-like task thread stuck on a socket read that never returns
        ServerSocket server = new ServerSocket(0);
        new Thread(() -> { try { server.accept(); sleep(Long.MAX_VALUE); } catch (IOException e) { } }, "fake-server").start();
        new Thread(() -> {
            try (Socket s = new Socket("localhost", server.getLocalPort())) { s.getInputStream().read(); } catch (IOException e) { }
        }, "task-thread-my-sink-connector-0").start();
        // leaking pool: a new parked thread every 300 ms
        ExecutorService[] leak = new ExecutorService[1];
        new Thread(() -> { for (int i = 0; ; i++) { ExecutorService e = Executors.newSingleThreadExecutor(); e.submit(() -> sleep(Long.MAX_VALUE)); sleep(300); } }, "leaker").start();
        sleep(Long.MAX_VALUE);
    }
}
