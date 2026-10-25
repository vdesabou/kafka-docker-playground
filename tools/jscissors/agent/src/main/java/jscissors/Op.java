package jscissors;

/** What a rule records on top of the call itself (enter / exit, duration and exception are always recorded). */
public enum Op {
    VALUES,             // arguments, on enter
    RETURN_VALUE,       // return value, on exit
    STACK,              // stack trace of the calling thread, on enter
    DELAY,              // duration: always recorded, kept for the rules of jscissors 1.0
    THREADS,            // thread dump, on enter
    RETURN_THREADS,     // thread dump, on exit
    EXCEPTION_THREADS,  // thread dump, when the method throws
    HEAP,               // heap dump, on enter
    RETURN_HEAP,        // heap dump, on exit
    EXCEPTION_HEAP      // heap dump, when the method throws
}
