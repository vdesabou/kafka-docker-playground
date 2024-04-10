List<MyPlatformEvent__e> myEvents = new List<MyPlatformEvent__e>();
myEvents.add(new MyPlatformEvent__e(Message__c ='test message 1'));
myEvents.add(new MyPlatformEvent__e(Message__c ='test message 2'));


// Call method to publish events
List<Database.SaveResult> results = EventBus.publish(myEvents);

// Inspect publishing result for each event
for (Database.SaveResult sr : results) {
    if (sr.isSuccess()) {
        System.debug('Successfully published event.');
    } else {
        for(Database.Error err : sr.getErrors()) {
            System.debug('Error returned: ' +
                        err.getStatusCode() +
                        ' - ' +
                        err.getMessage());
        }
    }
}