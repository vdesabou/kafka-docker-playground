/*=========================================================================
 * Copyright (c) 2002-2014 Pivotal Software, Inc. All Rights Reserved.
 * This product is protected by U.S. and international copyright
 * and intellectual property laws. Pivotal products are covered by
 * more patents listed at http://www.pivotal.io/patents.
 *=========================================================================
 */


import java.util.List;

import org.apache.geode.cache.Declarable;
import org.apache.geode.cache.asyncqueue.AsyncEvent;
import org.apache.geode.cache.asyncqueue.AsyncEventListener;

/** MyAsyncEventListener (AsyncEventListener)
 */
public class MyAsyncEventListener implements AsyncEventListener, Declarable {

/** The process ID of the VM that created this listener */
public int whereIWasRegistered;

/** noArg constructor 
 */
public MyAsyncEventListener() {
   //whereIWasRegistered = ProcessMgr.getProcessId();   
}

/**
 * Counts events based on operation type
 */
public boolean processEvents(List<AsyncEvent> events) {
    //just throw it away
    return true;
}

public void init(java.util.Properties prop) {
   //logCall("init(Properties)", null);
}

public void close() {
   //logCall("close", null);
}

/** Log that a gateway event occurred.
 *
 *  @param event The event object that was passed to the event.
 */
public String logCall(String methodName, AsyncEvent event) {
   String aStr = toString(methodName, event);
   //Log.getLogWriter().info(aStr);
   return aStr;
}


/** Return a string description of the GatewayEvent.
 *
 *  @param event The AsyncEvent object that was passed to the CqListener
 *
 *  @return A String description of the invoked GatewayEvent
 */
public String toString(String methodName, AsyncEvent event) {
   StringBuffer aStr = new StringBuffer();

   aStr.append("Invoked " + this.getClass().getName() + ": " + methodName + "  ");
   aStr.append(", whereIWasRegistered: " + whereIWasRegistered);

   if (event == null) {
     return aStr.toString();
   }
   aStr.append(", Event:" + event);
   return aStr.toString();
}  
}
