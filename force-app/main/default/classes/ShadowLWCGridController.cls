public with sharing class ShadowLWCGridController {
    
    @AuraEnabled(cacheable=true)
    public static Opty_Sd__c getScheduleData(Id recordId) {
        try {
            return [
                SELECT Id, Name, 
                       Amount0__c, Month0__c, Reason0__c,
                       Amount1__c, Month1__c, Reason1__c,
                       Amount2__c, Month2__c, Reason2__c,
                       Amount3__c, Month3__c, Reason3__c,
                       Amount4__c, Month4__c, Reason4__c,
                       Amount5__c, Month5__c, Reason5__c,
                       Opportunity__c
                FROM Opty_Sd__c 
                WHERE Id = :recordId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching schedule data: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Opty_Sd__c updateScheduleRecord(Opty_Sd__c record) {
        try {
            update record;
            return record;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating record: ' + e.getMessage());
        }
    }
}