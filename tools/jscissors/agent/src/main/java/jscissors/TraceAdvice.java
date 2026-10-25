package jscissors;

import net.bytebuddy.asm.Advice;
import net.bytebuddy.implementation.bytecode.assign.Assigner;

/** Inlined in the traced methods of a rule with VALUES. suppress: the advice can never break the traced method. */
public final class TraceAdvice {
    private TraceAdvice() {
    }

    @Advice.OnMethodEnter(suppress = Throwable.class)
    public static long enter(@RuleIndex int rule, @Advice.Origin("#t.#m#s") String origin, @Advice.AllArguments Object[] args) {
        return Tracer.enter(rule, origin, args);
    }

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    public static void exit(@RuleIndex int rule, @Advice.Enter long id, @Advice.Origin("#r") String returnType,
                            @Advice.Return(typing = Assigner.Typing.DYNAMIC) Object returned, @Advice.Thrown Throwable thrown) {
        Tracer.exit(rule, id, returnType, returned, thrown);
    }
}
