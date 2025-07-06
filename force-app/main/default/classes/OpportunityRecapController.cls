// OpportunityRecapController.cls - REWRITTEN with forecast vs reality logic
public with sharing class OpportunityRecapController {
    
    /**
     * Get opportunity recap showing what happened to opportunities that were forecasted 
     * to close in the target month (forecast vs reality analysis)
     */
    @AuraEnabled(cacheable=true)
    public static OpportunityRecapWrapper getOpportunityRecap(Integer year, Integer month) {
        try {
            // Calculate the target month we're analyzing (the "previous" month)
            Date targetStartDate = Date.newInstance(year, month, 1);
            Date targetEndDate = Date.newInstance(year, month, Date.daysInMonth(year, month));
            
            // Get current forecast month to determine which historical position to look at
            String currentForecastMonth = ForecastUtilityService.getCurrentForecastMonth();
            String previousForecastMonth = getPreviousForecastMonth(currentForecastMonth);
            
            // Step 1: Get unique opportunities that were FORECASTED to close in the target month
            // Use GROUP BY to get one record per opportunity to avoid duplicates
            List<AggregateResult> forecastedOpportunityIds = [
                SELECT Opportunity__c oppId
                FROM Opty_Sd__c 
                WHERE Month1__c = :previousForecastMonth
                AND CloseDate1__c >= :targetStartDate
                AND CloseDate1__c <= :targetEndDate
                AND Amount1__c > 0  // Had revenue forecasted for this month
                GROUP BY Opportunity__c
            ];
            
            // Extract the opportunity IDs
            Set<Id> opportunityIds = new Set<Id>();
            for (AggregateResult ar : forecastedOpportunityIds) {
                opportunityIds.add((Id)ar.get('oppId'));
            }
            
            // Step 2: Get the opportunity details and one snapshot record per opportunity for reasons
            Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>([
                SELECT Id, Name, StageName, Amount, CloseDate,
                       Account.Id, Account.Name, Owner.Name, LastModifiedDate
                FROM Opportunity 
                WHERE Id IN :opportunityIds
            ]);
            
            // Get one snapshot record per opportunity for the reason data
            List<Opty_Sd__c> snapshotReasons = [
                SELECT Opportunity__c, Reason1__c
                FROM Opty_Sd__c 
                WHERE Opportunity__c IN :opportunityIds
                AND Month1__c = :previousForecastMonth
                AND Reason1__c != null
                AND Reason1__c != ''
                LIMIT 1
            ];
            
            // Create a map of opportunity ID to reason
            Map<Id, String> opportunityReasonMap = new Map<Id, String>();
            for (Opty_Sd__c snapshot : snapshotReasons) {
                if (!opportunityReasonMap.containsKey(snapshot.Opportunity__c)) {
                    opportunityReasonMap.put(snapshot.Opportunity__c, snapshot.Reason1__c);
                }
            }
            
            // Step 3: Analyze what actually happened to each forecasted opportunity
            List<Opportunity> wonOpportunities = new List<Opportunity>();
            List<Opportunity> lostOpportunities = new List<Opportunity>();
            List<Opportunity> shiftedOpportunities = new List<Opportunity>();
            Map<Id, String> oppIdToReasonMap = new Map<Id, String>();
            
            for (Id oppId : opportunityIds) {
                Opportunity currentState = opportunityMap.get(oppId);
                if (currentState == null) continue;
                
                if (currentState.StageName == 'Closed Won') {
                    // This was forecasted for the target month and actually won
                    wonOpportunities.add(currentState);
                } else if (currentState.StageName == 'Closed Lost') {
                    // This was forecasted for the target month but lost
                    lostOpportunities.add(currentState);
                    // Store the reason from the snapshot data
                    if (opportunityReasonMap.containsKey(oppId)) {
                        oppIdToReasonMap.put(oppId, opportunityReasonMap.get(oppId));
                    }
                } else if (currentState.CloseDate > targetEndDate) {
                    // This was forecasted for the target month but date shifted out
                    shiftedOpportunities.add(currentState);
                    // Store the reason from the snapshot data
                    if (opportunityReasonMap.containsKey(oppId)) {
                        oppIdToReasonMap.put(oppId, opportunityReasonMap.get(oppId));
                    }
                }
                // Note: Opportunities that were forecasted but are still open within the target month
                // are not included in any category (they're just still pending)
            }
            
            // Step 4: Find opportunities CREATED during the target month
            List<Opportunity> createdOpportunities = [
                SELECT Id, Name, Amount, CloseDate, Account.Id, Account.Name, 
                       Owner.Name, StageName, CreatedDate
                FROM Opportunity 
                WHERE CreatedDate >= :targetStartDate 
                AND CreatedDate <= :targetEndDate
                ORDER BY CreatedDate DESC, Amount DESC
            ];
            
            // Build and return the wrapper
            OpportunityRecapWrapper wrapper = new OpportunityRecapWrapper();
            wrapper.wonOpportunities = wonOpportunities;
            wrapper.lostOpportunities = lostOpportunities;
            wrapper.shiftedOpportunities = shiftedOpportunities;
            wrapper.createdOpportunities = createdOpportunities;
            wrapper.oppIdToReasonMap = oppIdToReasonMap;
            
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error in getOpportunityRecap: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving opportunity data: ' + e.getMessage());
        }
    }
    
    /**
     * Alternative method to get opportunities that CHANGED to Closed Won/Lost during a month
     * Uses OpportunityFieldHistory if Field History tracking is enabled
     */
    @AuraEnabled
    public static OpportunityRecapWrapper getOpportunityRecapByStageChange(Integer year, Integer month) {
        try {
            Date startDate = Date.newInstance(year, month, 1);
            Date endDate = Date.newInstance(year, month, Date.daysInMonth(year, month));
                        
            // Query all stage changes in the specified month and filter in Apex
            List<OpportunityFieldHistory> stageChanges = [
                SELECT OpportunityId, NewValue, OldValue, CreatedDate
                FROM OpportunityFieldHistory 
                WHERE Field = 'StageName' 
                AND CreatedDate >= :startDate 
                AND CreatedDate <= :endDate
            ];
            
            Set<Id> opportunityIds = new Set<Id>();
            Map<Id, String> oppIdToStage = new Map<Id, String>();
                        
            // Filter for Closed Won/Lost in Apex since we can't filter NewValue in SOQL
            for (OpportunityFieldHistory history : stageChanges) {
                String newStage = (String)history.NewValue;
                if (newStage == 'Closed Won' || newStage == 'Closed Lost') {
                    opportunityIds.add(history.OpportunityId);
                    oppIdToStage.put(history.OpportunityId, newStage);
                }
            }
            
            List<Opportunity> allOpportunities = [
                SELECT Id, Name, Amount, CloseDate, Account.Id, Account.Name, 
                       Owner.Name, StageName, LastModifiedDate
                FROM Opportunity 
                WHERE Id IN :opportunityIds
                ORDER BY CloseDate DESC, Amount DESC
            ];
            
            List<Opportunity> wonOpportunities = new List<Opportunity>();
            List<Opportunity> lostOpportunities = new List<Opportunity>();
            
            for (Opportunity opp : allOpportunities) {
                String stageFromHistory = oppIdToStage.get(opp.Id);
                if (stageFromHistory == 'Closed Won') {
                    wonOpportunities.add(opp);
                } else if (stageFromHistory == 'Closed Lost') {
                    lostOpportunities.add(opp);
                }
            }
            
            OpportunityRecapWrapper wrapper = new OpportunityRecapWrapper();
            wrapper.wonOpportunities = wonOpportunities;
            wrapper.lostOpportunities = lostOpportunities;
            wrapper.shiftedOpportunities = new List<Opportunity>(); // Not applicable for stage change method
            wrapper.createdOpportunities = new List<Opportunity>(); // Not applicable for stage change method
            wrapper.oppIdToReasonMap = new Map<Id, String>(); // Empty map for stage change method
            
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error in getOpportunityRecapByStageChange: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving opportunity stage change data: ' + e.getMessage());
        }
    }
    
    /**
     * Helper method to determine which historical position to look at
     * This calculates the previous forecast month from the current one
     */
    private static String getPreviousForecastMonth(String currentMonth) {
        try {
            Date currentDate = ForecastUtilityService.parseDateString(currentMonth);
            Date previousMonth = currentDate.addMonths(-1);
            return ForecastUtilityService.formatDateString(previousMonth);
        } catch (Exception e) {
            System.debug('Error calculating previous forecast month: ' + e.getMessage());
            // Fallback to a reasonable default
            return '1/1/2025';
        }
    }
    
    /**
     * Wrapper class to hold all opportunity recap data
     */
    public class OpportunityRecapWrapper {
        @AuraEnabled
        public List<Opportunity> wonOpportunities;
        
        @AuraEnabled
        public List<Opportunity> lostOpportunities;
        
        @AuraEnabled
        public List<Opportunity> shiftedOpportunities;
        
        @AuraEnabled
        public List<Opportunity> createdOpportunities;
        
        @AuraEnabled
        public Map<Id, String> oppIdToReasonMap;
        
        public OpportunityRecapWrapper() {
            this.wonOpportunities = new List<Opportunity>();
            this.lostOpportunities = new List<Opportunity>();
            this.shiftedOpportunities = new List<Opportunity>();
            this.createdOpportunities = new List<Opportunity>();
            this.oppIdToReasonMap = new Map<Id, String>();
        }
    }
}