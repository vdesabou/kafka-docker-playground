package jscissors;

import net.bytebuddy.asm.Advice;
import net.bytebuddy.implementation.bytecode.assign.Assigner;

/** Same as TraceAdvice, without boxing the arguments: rules without VALUES. */
public final class TraceAdviceNoArgs {
    private TraceAdviceNoArgs() {
    }

    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static long enter(@RuleIndex int rule, @Advice.Origin("#t.#m#s") String origin) {
        return Tracer.enter(rule, origin, null);
    }

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    public static void exit(@RuleIndex int rule, @Advice.Enter long id, @Advice.Origin("#r") String returnType,
                            @Advice.Return(typing = Assigner.Typing.DYNAMIC) Object returned, @Advice.Thrown Throwable thrown) {
        Tracer.exit(rule, id, returnType, returned, thrown);
    }
}
