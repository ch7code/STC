// Replace 'Opportunity' with your actual object name
List<Opportunity> recordsToDelete = [SELECT Id FROM Opportunity];

if (!recordsToDelete.isEmpty()) {
    delete recordsToDelete;
    System.debug('Deleted ' + recordsToDelete.size() + ' records');
} else {
    System.debug('No records found to delete');
}