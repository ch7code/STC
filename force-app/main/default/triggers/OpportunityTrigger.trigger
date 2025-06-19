trigger OpportunityTrigger on Opportunity (after insert, after update) {
    
    System.debug('OpportunityTrigger fired! Context: ' + Trigger.operationType);
    System.debug('Number of records: ' + Trigger.new.size());
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            System.debug('Calling createOpportunitySnapshots for INSERT');
            // Create snapshots for new opportunities
            OpportunitySnapshotHandler.createOpportunitySnapshots(Trigger.new);
        }
        
        if (Trigger.isUpdate) {
            System.debug('Calling updateOpportunitySnapshots for UPDATE');
            // Update snapshots for modified opportunities
            OpportunitySnapshotHandler.updateOpportunitySnapshots(Trigger.new, Trigger.oldMap);
        }
    }
}