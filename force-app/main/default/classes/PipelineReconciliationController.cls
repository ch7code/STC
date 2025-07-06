// PipelineReconciliationController.cls
public with sharing class PipelineReconciliationController {
    
    /**
     * Get pipeline reconciliation data showing what happened to forecasted opportunities
     * and how individual changes add up to the total M0-M1 pipeline change
     */
    @AuraEnabled(cacheable=true)
    public static PipelineReconciliationWrapper getPipelineReconciliation(Integer year, Integer month) {
        try {
            // Calculate the target month we're analyzing
            Date targetStartDate = Date.newInstance(year, month, 1);
            Date targetEndDate = Date.newInstance(year, month, Date.daysInMonth(year, month));
            
            // Get current and previous forecast months
            String currentForecastMonth = ForecastUtilityService.getCurrentForecastMonth();
            String previousForecastMonth = getPreviousForecastMonth(currentForecastMonth);
            
            // Step 1: Get all opportunities that were forecasted in the target month (M1 position)
            List<AggregateResult> forecastedOpportunityIds = [
                SELECT Opportunity__c oppId
                FROM Opty_Sd__c 
                WHERE Month1__c = :previousForecastMonth
                AND CloseDate1__c >= :targetStartDate
                AND CloseDate1__c <= :targetEndDate
                AND Amount1__c > 0
                GROUP BY Opportunity__c
            ];
            
            Set<Id> forecastedOppIds = new Set<Id>();
            for (AggregateResult ar : forecastedOpportunityIds) {
                forecastedOppIds.add((Id)ar.get('oppId'));
            }
            
            // Step 2: Get current state of forecasted opportunities
            Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>([
                SELECT Id, Name, StageName, Amount, CloseDate, CreatedDate,
                       Account.Id, Account.Name, Owner.Name, LastModifiedDate,
                       Period_of_Performance__c, Reason_for_Change__c
                FROM Opportunity 
                WHERE Id IN :forecastedOppIds
            ]);
            
            // Step 3: Get snapshot data for amounts and reasons
            Map<Id, OpportunitySnapshot> snapshotMap = getSnapshotData(forecastedOppIds, previousForecastMonth);
            
            // Step 4: Get opportunities created during target month
            List<Opportunity> createdInMonth = [
                SELECT Id, Name, StageName, Amount, CloseDate, CreatedDate,
                       Account.Id, Account.Name, Owner.Name, Period_of_Performance__c
                FROM Opportunity 
                WHERE CreatedDate >= :targetStartDate 
                AND CreatedDate <= :targetEndDate
                AND Id NOT IN :forecastedOppIds  // Exclude already forecasted ones
            ];
            
            // Step 5: Categorize opportunities using priority rules
            PipelineReconciliationWrapper wrapper = categorizeOpportunities(
                opportunityMap, snapshotMap, createdInMonth, targetStartDate, targetEndDate
            );
            
            // Step 6: Calculate pipeline totals and reconciliation
            calculatePipelineReconciliation(wrapper, snapshotMap);
            
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error in getPipelineReconciliation: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving pipeline reconciliation data: ' + e.getMessage());
        }
    }
    
    /**
     * Get snapshot data for opportunities to track changes
     */
    private static Map<Id, OpportunitySnapshot> getSnapshotData(Set<Id> oppIds, String previousForecastMonth) {
        Map<Id, OpportunitySnapshot> snapshotMap = new Map<Id, OpportunitySnapshot>();
        
        // Get snapshot records for opportunities with M0 and M1 data
        List<Opty_Sd__c> snapshots = [
            SELECT Opportunity__c, Amount0__c, Amount1__c, CloseDate0__c, CloseDate1__c,
                   Reason0__c, Reason1__c, Revenue_Date__c
            FROM Opty_Sd__c 
            WHERE Opportunity__c IN :oppIds
            AND Month1__c = :previousForecastMonth
            LIMIT 1000
        ];
        
        // Aggregate by opportunity to get totals
        Map<Id, Decimal> m0Totals = new Map<Id, Decimal>();
        Map<Id, Decimal> m1Totals = new Map<Id, Decimal>();
        Map<Id, String> reasons = new Map<Id, String>();
        Map<Id, Date> closeDates0 = new Map<Id, Date>();
        Map<Id, Date> closeDates1 = new Map<Id, Date>();
        
        for (Opty_Sd__c snapshot : snapshots) {
            Id oppId = snapshot.Opportunity__c;
            
            // Aggregate amounts
            if (!m0Totals.containsKey(oppId)) {
                m0Totals.put(oppId, 0);
                m1Totals.put(oppId, 0);
            }
            m0Totals.put(oppId, m0Totals.get(oppId) + (snapshot.Amount0__c ?? 0));
            m1Totals.put(oppId, m1Totals.get(oppId) + (snapshot.Amount1__c ?? 0));
            
            // Store other data (first record wins)
            if (!reasons.containsKey(oppId) && String.isNotBlank(snapshot.Reason0__c)) {
                reasons.put(oppId, snapshot.Reason0__c);
            }
            if (!closeDates0.containsKey(oppId)) {
                closeDates0.put(oppId, snapshot.CloseDate0__c);
                closeDates1.put(oppId, snapshot.CloseDate1__c);
            }
        }
        
        // Build snapshot objects
        for (Id oppId : oppIds) {
            OpportunitySnapshot snap = new OpportunitySnapshot();
            snap.opportunityId = oppId;
            snap.currentAmount = m0Totals.get(oppId) ?? 0;
            snap.previousAmount = m1Totals.get(oppId) ?? 0;
            snap.amountDelta = snap.currentAmount - snap.previousAmount;
            snap.currentCloseDate = closeDates0.get(oppId);
            snap.previousCloseDate = closeDates1.get(oppId);
            snap.reason = reasons.get(oppId) ?? '';
            snapshotMap.put(oppId, snap);
        }
        
        return snapshotMap;
    }
    
    /**
     * Categorize opportunities using priority classification rules
     */
    private static PipelineReconciliationWrapper categorizeOpportunities(
        Map<Id, Opportunity> opportunityMap, 
        Map<Id, OpportunitySnapshot> snapshotMap,
        List<Opportunity> createdInMonth,
        Date targetStartDate, 
        Date targetEndDate
    ) {
        PipelineReconciliationWrapper wrapper = new PipelineReconciliationWrapper();
        
        // Process forecasted opportunities
        for (Id oppId : opportunityMap.keySet()) {
            Opportunity opp = opportunityMap.get(oppId);
            OpportunitySnapshot snap = snapshotMap.get(oppId);
            
            if (opp.StageName == 'Closed Won') {
                // Priority 1: Won (regardless of other factors)
                OpportunityChange change = createOpportunityChange(opp, snap, 'Won');
                if (opp.CreatedDate >= targetStartDate && opp.CreatedDate <= targetEndDate) {
                    change.metadata = 'Created & Won same month';
                } else if (snap != null && snap.previousCloseDate != opp.CloseDate) {
                    change.metadata = 'Shifted from ' + formatDateValue(snap.previousCloseDate) + ', Won in ' + formatDateValue(opp.CloseDate);
                }
                wrapper.wonOpportunities.add(change);
                wrapper.wonTotal += opp.Amount ?? 0;
                
            } else if (opp.StageName == 'Closed Lost') {
                // Priority 2: Lost (regardless of other factors)
                OpportunityChange change = createOpportunityChange(opp, snap, 'Lost');
                wrapper.lostOpportunities.add(change);
                wrapper.lostTotal += opp.Amount ?? 0;
                
            } else if (opp.CreatedDate >= targetStartDate && opp.CreatedDate <= targetEndDate) {
                // Priority 3: Created (but only if still open)
                OpportunityChange change = createOpportunityChange(opp, snap, 'Created');
                change.metadata = 'Created ' + formatDateValue(opp.CreatedDate) + ', closes ' + formatDateValue(opp.CloseDate);
                wrapper.createdOpportunities.add(change);
                wrapper.createdTotal += opp.Amount ?? 0;
                
            } else if (opp.CloseDate > targetEndDate || 
                      (snap.previousCloseDate != null && snap.previousCloseDate <= targetEndDate && opp.CloseDate > targetEndDate)) {
                // Priority 4: Shifted (date moved out of target month)
                OpportunityChange change = createOpportunityChange(opp, snap, 'Shifted');
                change.metadata = 'Shifted from ' + formatDateValue(snap.previousCloseDate) + ' to ' + formatDateValue(opp.CloseDate);
                wrapper.shiftedOpportunities.add(change);
                // Shifted opportunities don't affect total pipeline (still there, just different timing)
                
            } else if (snap.amountDelta != 0) {
                // Amount/Stage/POP changes for opportunities still in target month
                OpportunityChange change = createOpportunityChange(opp, snap, 'Changed');
                change.metadata = buildChangeMetadata(snap);
                wrapper.changedOpportunities.add(change);
                wrapper.changedTotal += snap.amountDelta;
            }
        }
        
        // Process opportunities created in month (that weren't already processed)
        for (Opportunity opp : createdInMonth) {
            if (opp.StageName == 'Closed Won') {
                // Created and won same month - goes to Won category
                OpportunityChange change = new OpportunityChange();
                change.opportunity = opp;
                change.category = 'Won';
                change.metadata = 'Created & Won same month';
                change.amountDelta = -(opp.Amount ?? 0); // Negative because removed from pipeline
                wrapper.wonOpportunities.add(change);
                wrapper.wonTotal += opp.Amount ?? 0;
                
            } else if (opp.StageName == 'Closed Lost') {
                // Created and lost same month - goes to Lost category  
                OpportunityChange change = new OpportunityChange();
                change.opportunity = opp;
                change.category = 'Lost';
                change.metadata = 'Created & Lost same month';
                change.amountDelta = 0; // Net zero impact (added then removed)
                wrapper.lostOpportunities.add(change);
                
            } else {
                // Created and still open - goes to Created category
                OpportunityChange change = new OpportunityChange();
                change.opportunity = opp;
                change.category = 'Created';
                change.metadata = 'Created ' + formatDateValue(opp.CreatedDate) + ', closes ' + formatDateValue(opp.CloseDate);
                change.amountDelta = opp.Amount ?? 0; // Positive because added to pipeline
                wrapper.createdOpportunities.add(change);
                wrapper.createdTotal += opp.Amount ?? 0;
            }
        }
        
        return wrapper;
    }
    
    /**
     * Calculate pipeline reconciliation totals
     */
    private static void calculatePipelineReconciliation(PipelineReconciliationWrapper wrapper, Map<Id, OpportunitySnapshot> snapshotMap) {
        // Calculate M1 total (previous month pipeline)
        wrapper.previousPipelineTotal = 0;
        for (OpportunitySnapshot snap : snapshotMap.values()) {
            wrapper.previousPipelineTotal += snap.previousAmount;
        }
        
        // Calculate M0 total (current month pipeline) 
        wrapper.currentPipelineTotal = 0;
        for (OpportunitySnapshot snap : snapshotMap.values()) {
            wrapper.currentPipelineTotal += snap.currentAmount;
        }
        
        // Calculate net change
        wrapper.netPipelineChange = wrapper.currentPipelineTotal - wrapper.previousPipelineTotal;
        
        // Reconciliation check (should add up to net change)
        wrapper.reconciliationTotal = 
            (-wrapper.wonTotal) +           // Won opportunities removed from pipeline
            (-wrapper.lostTotal) +          // Lost opportunities removed from pipeline  
            wrapper.createdTotal +          // Created opportunities added to pipeline
            wrapper.changedTotal;           // Amount changes to existing opportunities
            // Shifted opportunities = 0 impact (still in pipeline)
    }
    
    /**
     * Helper methods
     */
    private static OpportunityChange createOpportunityChange(Opportunity opp, OpportunitySnapshot snap, String category) {
        OpportunityChange change = new OpportunityChange();
        change.opportunity = opp;
        change.snapshot = snap;
        change.category = category;
        
        if (category == 'Won' || category == 'Lost') {
            change.amountDelta = -(opp.Amount ?? 0); // Removed from pipeline
        } else if (category == 'Created') {
            change.amountDelta = opp.Amount ?? 0; // Added to pipeline
        } else if (category == 'Changed') {
            change.amountDelta = snap.amountDelta; // Net change
        } else {
            change.amountDelta = 0; // Shifted = no net impact
        }
        
        return change;
    }
    
    private static String buildChangeMetadata(OpportunitySnapshot snap) {
        List<String> changes = new List<String>();
        if (snap.amountDelta > 0) {
            changes.add('Amount +' + String.valueOf(snap.amountDelta.setScale(0)));
        } else if (snap.amountDelta < 0) {
            changes.add('Amount ' + String.valueOf(snap.amountDelta.setScale(0)));
        }
        if (String.isNotBlank(snap.reason)) {
            changes.add(snap.reason);
        }
        return String.join(changes, ', ');
    }
    
    private static String formatDateValue(Date dateValue) {
        if (dateValue == null) return '';
        return dateValue.format();
    }
    
    private static String formatDateValue(Datetime datetimeValue) {
        if (datetimeValue == null) return '';
        return datetimeValue.date().format();
    }
    
    private static String getPreviousForecastMonth(String currentMonth) {
        try {
            Date currentDate = ForecastUtilityService.parseDateString(currentMonth);
            Date previousMonth = currentDate.addMonths(-1);
            return ForecastUtilityService.formatDateString(previousMonth);
        } catch (Exception e) {
            return '1/1/2025';
        }
    }
    
    /**
     * Wrapper classes
     */
    public class PipelineReconciliationWrapper {
        @AuraEnabled public List<OpportunityChange> wonOpportunities = new List<OpportunityChange>();
        @AuraEnabled public List<OpportunityChange> lostOpportunities = new List<OpportunityChange>();
        @AuraEnabled public List<OpportunityChange> createdOpportunities = new List<OpportunityChange>();
        @AuraEnabled public List<OpportunityChange> shiftedOpportunities = new List<OpportunityChange>();
        @AuraEnabled public List<OpportunityChange> changedOpportunities = new List<OpportunityChange>();
        
        @AuraEnabled public Decimal wonTotal = 0;
        @AuraEnabled public Decimal lostTotal = 0;
        @AuraEnabled public Decimal createdTotal = 0;
        @AuraEnabled public Decimal changedTotal = 0;
        
        @AuraEnabled public Decimal previousPipelineTotal = 0;  // M1
        @AuraEnabled public Decimal currentPipelineTotal = 0;   // M0
        @AuraEnabled public Decimal netPipelineChange = 0;      // M0 - M1
        @AuraEnabled public Decimal reconciliationTotal = 0;    // Sum of all changes (should equal netPipelineChange)
    }
    
    public class OpportunityChange {
        @AuraEnabled public Opportunity opportunity;
        @AuraEnabled public OpportunitySnapshot snapshot;
        @AuraEnabled public String category;
        @AuraEnabled public String metadata;
        @AuraEnabled public Decimal amountDelta;
    }
    
    public class OpportunitySnapshot {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Decimal currentAmount;
        @AuraEnabled public Decimal previousAmount;
        @AuraEnabled public Decimal amountDelta;
        @AuraEnabled public Date currentCloseDate;
        @AuraEnabled public Date previousCloseDate;
        @AuraEnabled public String reason;
    }
}