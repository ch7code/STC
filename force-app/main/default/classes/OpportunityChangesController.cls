public with sharing class OpportunityChangesController {
    
    @AuraEnabled(cacheable=true)
    public static List<OpportunityChangeWrapper> getOpportunityChanges() {
        try {
            List<OpportunityChangeWrapper> changes = new List<OpportunityChangeWrapper>();
            
            // Get current forecast month to determine "last month"
            String currentMonthStr = ForecastUtilityService.getCurrentForecastMonth();
            Date currentForecastMonth = ForecastUtilityService.parseDateString(currentMonthStr);
            Date lastMonth = currentForecastMonth.addMonths(-1);
            String lastMonthStr = ForecastUtilityService.formatDateString(lastMonth);
            
            // Query snapshots - get one record per opportunity where Month0 = current month
            List<Opty_Sd__c> snapshots = [
                SELECT Id, 
                       Opportunity__c,
                       Opportunity__r.Name,
                       Opportunity__r.Account.Name,
                       Opportunity__r.StageName,
                       Opportunity__r.Amount,
                       Amount0__c,
                       Amount1__c,
                       Reason0__c,
                       Month0__c,
                       Month1__c
                FROM Opty_Sd__c
                WHERE Opportunity__c != null
                AND Month0__c = :currentMonthStr
                AND Month1__c = :lastMonthStr
                ORDER BY Opportunity__r.Account.Name, Opportunity__r.Name
            ];
            
            for (Opty_Sd__c snapshot : snapshots) {
                String changeType = determineChangeType(snapshot);
                
                // Only include records that had meaningful changes
                if (changeType != 'No Change') {
                    OpportunityChangeWrapper wrapper = new OpportunityChangeWrapper();
                    wrapper.id = snapshot.Opportunity__c;
                    wrapper.accountName = snapshot.Opportunity__r.Account.Name;
                    wrapper.opportunityName = snapshot.Opportunity__r.Name;
                    wrapper.stageName = snapshot.Opportunity__r.StageName;
                    wrapper.amountBefore = snapshot.Amount1__c != null ? snapshot.Amount1__c : 0;
                    wrapper.amountAfter = snapshot.Amount0__c != null ? snapshot.Amount0__c : 0;
                    wrapper.changeType = changeType;
                    
                    changes.add(wrapper);
                }
            }
            
            return changes;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving opportunity changes: ' + e.getMessage());
        }
    }
    
    private static String determineChangeType(Opty_Sd__c snapshot) {
        String currentReason = snapshot.Reason0__c;
        Decimal amountBefore = snapshot.Amount1__c != null ? snapshot.Amount1__c : 0;
        Decimal amountAfter = snapshot.Amount0__c != null ? snapshot.Amount0__c : 0;
        
        // Check for closures first
        if (currentReason == 'Closed Won') {
            return 'Closed Won';
        } else if (currentReason == 'Closed Lost') {
            return 'Closed Lost';
        }
        
        // Check for significant amount changes (could indicate date shifts)
        Decimal threshold = 0.01; // 1 cent threshold for comparison
        if (Math.abs(amountBefore - amountAfter) > threshold) {
            if (amountAfter < amountBefore * 0.5) {
                return 'Date Shifted'; // Significant decrease likely means shifted out
            } else if (amountAfter > amountBefore * 1.5) {
                return 'Date Shifted'; // Significant increase likely means shifted in
            } else {
                return 'Amount Changed';
            }
        }
        
        return 'No Change';
    }
    
    // Wrapper class for LWC data
    public class OpportunityChangeWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String accountName;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amountBefore;
        @AuraEnabled public Decimal amountAfter;
        @AuraEnabled public String changeType;
    }
}