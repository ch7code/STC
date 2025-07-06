// PipelineMathController.cls
public with sharing class PipelineMathController {
    
    @AuraEnabled(cacheable=true)
    public static PipelineMathWrapper getPipelineMath(Integer year, Integer month, Boolean includeWonRevenue) {
        try {
            // Calculate target month (previous month we're analyzing)
            Date targetStartDate = Date.newInstance(year, month, 1);
            Date targetEndDate = Date.newInstance(year, month, Date.daysInMonth(year, month));
            
            // Calculate 12M Forward window (current month + 11 months)
            Date forwardStartDate = targetEndDate.addDays(1); // Start of next month
            Date forwardEndDate = forwardStartDate.addMonths(12).addDays(-1); // End of 12th month
            
            // Get current and previous forecast months
            String currentForecastMonth = ForecastUtilityService.getCurrentForecastMonth();
            String previousForecastMonth = getPreviousForecastMonth(currentForecastMonth);
            
            PipelineMathWrapper wrapper = new PipelineMathWrapper();
            wrapper.analysisMonth = getMonthName(month) + ' ' + year;
            wrapper.forwardPeriod = getMonthName(forwardStartDate.month()) + ' ' + forwardStartDate.year() + 
                                   ' - ' + getMonthName(forwardEndDate.month()) + ' ' + forwardEndDate.year();
            wrapper.includeWonRevenue = includeWonRevenue;
            
            // STEP 1: Calculate 12M Forward totals (M0 vs M1)
            calculate12MForwardTotals(wrapper, forwardStartDate, forwardEndDate, previousForecastMonth);
            
            // STEP 2: Get all opportunities that affect the analysis
            Map<Id, Opportunity> allOpportunities = getAllRelevantOpportunities(
                targetStartDate, targetEndDate, forwardStartDate, forwardEndDate, previousForecastMonth
            );
            
            // STEP 3: Categorize opportunities and calculate 12M Forward impacts
            System.debug('Total opportunities to categorize: ' + allOpportunities.size());
            categorizeOpportunityImpacts(wrapper, allOpportunities, targetStartDate, targetEndDate, 
                                       forwardStartDate, forwardEndDate, previousForecastMonth, includeWonRevenue);
            
            System.debug('Red items: ' + wrapper.redItems.size() + ', total: ' + wrapper.redTotal);
            System.debug('Green items: ' + wrapper.greenItems.size() + ', total: ' + wrapper.greenTotal);
            System.debug('Gray items: ' + wrapper.grayItems.size() + ', total: ' + wrapper.grayTotal);
            
            // STEP 4: Verify reconciliation
            wrapper.reconciliationCheck = wrapper.redTotal + wrapper.greenTotal + wrapper.grayTotal;
            wrapper.isBalanced = Math.abs(wrapper.forward12MChange - wrapper.reconciliationCheck) < 100;
            
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error in getPipelineMath: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving pipeline math: ' + e.getMessage());
        }
    }
    
    /**
     * Calculate 12M Forward pipeline totals
     */
    private static void calculate12MForwardTotals(PipelineMathWrapper wrapper, Date forwardStart, Date forwardEnd, String previousMonth) {
        // Get all snapshot records in the 12M Forward window
        List<AggregateResult> forwardTotals = [
            SELECT 
                SUM(Amount0__c) currentTotal,
                SUM(Amount1__c) previousTotal
            FROM Opty_Sd__c
            WHERE Revenue_Date__c >= :forwardStart
            AND Revenue_Date__c <= :forwardEnd
        ];
        
        if (!forwardTotals.isEmpty()) {
            AggregateResult result = forwardTotals[0];
            wrapper.forward12MCurrent = (Decimal)(result.get('currentTotal') ?? 0);
            wrapper.forward12MPrevious = (Decimal)(result.get('previousTotal') ?? 0);
            wrapper.forward12MChange = wrapper.forward12MCurrent - wrapper.forward12MPrevious;
        }
        
        System.debug('12M Forward totals - Current: ' + wrapper.forward12MCurrent + 
                    ', Previous: ' + wrapper.forward12MPrevious + 
                    ', Change: ' + wrapper.forward12MChange);
    }
    
    /**
     * Get all opportunities that could affect the analysis
     */
    private static Map<Id, Opportunity> getAllRelevantOpportunities(
        Date targetStart, Date targetEnd, Date forwardStart, Date forwardEnd, String previousMonth
    ) {
        Set<Id> relevantOpportunityIds = new Set<Id>();
        
        // 1. Opportunities that were forecasted to close in target month (M1 position)
        List<AggregateResult> forecastedIds = [
            SELECT Opportunity__c oppId
            FROM Opty_Sd__c 
            WHERE Month1__c = :previousMonth
            AND CloseDate1__c >= :targetStart
            AND CloseDate1__c <= :targetEnd
            GROUP BY Opportunity__c
        ];
        
        for (AggregateResult ar : forecastedIds) {
            relevantOpportunityIds.add((Id)ar.get('oppId'));
        }
        
        // 2. Opportunities created in target month
        List<Opportunity> createdOpps = [
            SELECT Id FROM Opportunity 
            WHERE CreatedDate >= :targetStart 
            AND CreatedDate <= :targetEnd
        ];
        
        for (Opportunity opp : createdOpps) {
            relevantOpportunityIds.add(opp.Id);
        }
        
        // 3. ALL opportunities with ANY snapshot data in the 12M Forward window
        // This ensures we catch everything that affects the forward pipeline
        List<AggregateResult> anySnapshotIds = [
            SELECT Opportunity__c oppId
            FROM Opty_Sd__c 
            WHERE Revenue_Date__c >= :forwardStart
            AND Revenue_Date__c <= :forwardEnd
            GROUP BY Opportunity__c
        ];
        
        for (AggregateResult ar : anySnapshotIds) {
            relevantOpportunityIds.add((Id)ar.get('oppId'));
        }
        
        System.debug('Found ' + relevantOpportunityIds.size() + ' relevant opportunities');
        
        // Get all opportunity details
        return new Map<Id, Opportunity>([
            SELECT Id, Name, StageName, Amount, CloseDate, CreatedDate,
                   Account.Id, Account.Name, Owner.Name, 
                   Period_of_Performance__c, Reason_for_Change__c
            FROM Opportunity 
            WHERE Id IN :relevantOpportunityIds
        ]);
    }
    
    /**
     * Categorize opportunities and calculate their 12M Forward impact
     */
    private static void categorizeOpportunityImpacts(
        PipelineMathWrapper wrapper, 
        Map<Id, Opportunity> opportunities,
        Date targetStart, Date targetEnd,
        Date forwardStart, Date forwardEnd, 
        String previousMonth,
        Boolean includeWonRevenue
    ) {
        
        // Get 12M Forward impact for each opportunity
        Map<Id, OpportunityForwardImpact> forwardImpacts = calculate12MForwardImpacts(
            opportunities.keySet(), forwardStart, forwardEnd, previousMonth
        );
        
        for (Id oppId : opportunities.keySet()) {
            Opportunity opp = opportunities.get(oppId);
            OpportunityForwardImpact impact = forwardImpacts.get(oppId);
            
            if (impact == null) continue; // Skip if no impact data
            
            // Calculate the actual forward impact for this opportunity
            Decimal actualForwardImpact = impact.netImpact;
            
            PipelineMathItem item = new PipelineMathItem();
            item.opportunityName = opp.Name;
            item.accountName = opp.Account?.Name ?? '';
            item.currentAmount = opp.Amount ?? 0;
            item.forwardImpact = actualForwardImpact;
            item.reason = determineChangeReason(opp, targetStart, targetEnd, impact);
            
            // Skip opportunities with no meaningful impact (less than $100)
            // But always include Closed Won/Lost regardless of impact
            if (Math.abs(actualForwardImpact) < 100 && 
                opp.StageName != 'Closed Won' && 
                opp.StageName != 'Closed Lost') {
                continue;
            }
            
            // Handle Closed Won opportunities based on toggle
            if (opp.StageName == 'Closed Won') {
                if (includeWonRevenue) {
                    // GREEN: Include Won Revenue mode - show the actual positive change
                    item.category = 'green';
                    item.description = 'Closed Won - Revenue realized';
                    // Use the actual impact from snapshots, not POP revenue
                    wrapper.greenItems.add(item);
                    wrapper.greenTotal += actualForwardImpact; // This should already be positive
                } else {
                    // RED: Exclude Won Revenue mode - show pipeline removal as negative
                    item.category = 'red';
                    item.description = 'Closed Won - Removed from pipeline';
                    // Impact should already be negative, but ensure it
                    if (actualForwardImpact > 0) {
                        item.forwardImpact = -actualForwardImpact;
                    }
                    wrapper.redItems.add(item);
                    wrapper.redTotal += item.forwardImpact; // Add the negative impact
                }
                
            } else if (opp.StageName == 'Closed Lost') {
                // RED: Lost opportunities (always negative regardless of mode)
                item.category = 'red';
                item.description = 'Closed Lost - Revenue lost';
                wrapper.redItems.add(item);
                wrapper.redTotal += actualForwardImpact; // Should already be negative
                
            } else if (impact.previousForwardRevenue == 0 && impact.currentForwardRevenue > 0) {
                // GREEN: Newly created opportunities
                item.category = 'green';
                item.description = 'New opportunity - Added future revenue';
                wrapper.greenItems.add(item);
                wrapper.greenTotal += actualForwardImpact;
                
            } else if (opp.CreatedDate >= targetStart && opp.CreatedDate <= targetEnd) {
                // GREEN: Created opportunities (fallback)
                item.category = 'green';
                item.description = 'New opportunity - Added future revenue';
                wrapper.greenItems.add(item);
                wrapper.greenTotal += actualForwardImpact;
                
            } else if (actualForwardImpact > 0) {
                // GREEN: Positive changes to existing opportunities
                item.category = 'green';
                item.description = 'Increased future revenue';
                wrapper.greenItems.add(item);
                wrapper.greenTotal += actualForwardImpact;
                
            } else if (impact.isDateShiftOnly) {
                // GRAY: Date shifts with no net impact
                item.category = 'gray';
                item.description = 'Date shift - No net revenue change';
                wrapper.grayItems.add(item);
                wrapper.grayTotal += actualForwardImpact;
                
            } else {
                // RED: Negative changes to existing opportunities
                item.category = 'red';
                item.description = 'Decreased future revenue';
                wrapper.redItems.add(item);
                wrapper.redTotal += actualForwardImpact;
            }
        }
    }
    
    /**
     * Calculate 12M Forward impact for each opportunity
     */
    private static Map<Id, OpportunityForwardImpact> calculate12MForwardImpacts(
        Set<Id> opportunityIds, Date forwardStart, Date forwardEnd, String previousMonth
    ) {
        Map<Id, OpportunityForwardImpact> impacts = new Map<Id, OpportunityForwardImpact>();
        
        // Initialize all opportunities with empty impact
        for (Id oppId : opportunityIds) {
            OpportunityForwardImpact impact = new OpportunityForwardImpact();
            impact.currentForwardRevenue = 0;
            impact.previousForwardRevenue = 0;
            impact.netImpact = 0;
            impact.hasDateShift = false;
            impact.isDateShiftOnly = false;
            impacts.put(oppId, impact);
        }
        
        // Get ALL snapshot data for 12M Forward window
        List<Opty_Sd__c> snapshots = [
            SELECT Opportunity__c, Amount0__c, Amount1__c, Revenue_Date__c,
                   CloseDate0__c, CloseDate1__c, Month1__c
            FROM Opty_Sd__c
            WHERE Opportunity__c IN :opportunityIds
            AND Revenue_Date__c >= :forwardStart
            AND Revenue_Date__c <= :forwardEnd
        ];
        
        // Aggregate by opportunity
        for (Opty_Sd__c snapshot : snapshots) {
            Id oppId = snapshot.Opportunity__c;
            OpportunityForwardImpact impact = impacts.get(oppId);
            
            // Current amount is always Amount0__c
            impact.currentForwardRevenue += (snapshot.Amount0__c ?? 0);
            
            // Previous amount is always Amount1__c (regardless of Month1__c value)
            impact.previousForwardRevenue += (snapshot.Amount1__c ?? 0);
            
            // Check for date shifts
            if (snapshot.CloseDate0__c != snapshot.CloseDate1__c) {
                impact.hasDateShift = true;
            }
        }
        
        // Calculate net impacts
        for (Id oppId : impacts.keySet()) {
            OpportunityForwardImpact impact = impacts.get(oppId);
            impact.netImpact = impact.currentForwardRevenue - impact.previousForwardRevenue;
            impact.isDateShiftOnly = impact.hasDateShift && Math.abs(impact.netImpact) < 1000;
            
            System.debug('Impact for ' + oppId + ': Current=' + impact.currentForwardRevenue + 
                        ', Previous=' + impact.previousForwardRevenue + 
                        ', Net=' + impact.netImpact);
        }
        
        return impacts;
    }
    
    /**
     * Helper methods
     */
    private static String determineChangeReason(Opportunity opp, Date targetStart, Date targetEnd, OpportunityForwardImpact impact) {
        List<String> reasons = new List<String>();
        
        if (opp.StageName == 'Closed Won' || opp.StageName == 'Closed Lost') {
            reasons.add(opp.StageName);
        }
        
        if (opp.CreatedDate >= targetStart && opp.CreatedDate <= targetEnd) {
            reasons.add('Created in analysis period');
        }
        
        if (impact.hasDateShift) {
            reasons.add('Date shifted');
        }
        
        if (String.isNotBlank(opp.Reason_for_Change__c)) {
            reasons.add(opp.Reason_for_Change__c);
        }
        
        return String.join(reasons, ', ');
    }
    
    private static String getMonthName(Integer month) {
        List<String> monthNames = new List<String>{
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        };
        return monthNames[month - 1];
    }
    
    private static String getPreviousForecastMonth(String currentMonth) {
        try {
            Date currentDate = ForecastUtilityService.parseDateString(currentMonth);
            Date previousMonth = currentDate.addMonths(-1);
            return ForecastUtilityService.formatDateString(previousMonth);
        } catch (Exception e) {
            return '3/1/2025'; // Default to the value we know exists
        }
    }
    
    /**
     * Wrapper classes
     */
    public class PipelineMathWrapper {
        @AuraEnabled public String analysisMonth;
        @AuraEnabled public String forwardPeriod;
        @AuraEnabled public Boolean includeWonRevenue = false;
        @AuraEnabled public Decimal forward12MPrevious = 0;
        @AuraEnabled public Decimal forward12MCurrent = 0;
        @AuraEnabled public Decimal forward12MChange = 0;
        
        @AuraEnabled public List<PipelineMathItem> redItems = new List<PipelineMathItem>();
        @AuraEnabled public List<PipelineMathItem> greenItems = new List<PipelineMathItem>();
        @AuraEnabled public List<PipelineMathItem> grayItems = new List<PipelineMathItem>();
        
        @AuraEnabled public Decimal redTotal = 0;
        @AuraEnabled public Decimal greenTotal = 0;
        @AuraEnabled public Decimal grayTotal = 0;
        @AuraEnabled public Decimal reconciliationCheck = 0;
        @AuraEnabled public Boolean isBalanced = false;
    }
    
    public class PipelineMathItem {
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Decimal currentAmount;
        @AuraEnabled public Decimal forwardImpact;
        @AuraEnabled public String reason;
        @AuraEnabled public String category;
        @AuraEnabled public String description;
    }
    
    public class OpportunityForwardImpact {
        public Decimal currentForwardRevenue = 0;
        public Decimal previousForwardRevenue = 0;
        public Decimal netImpact = 0;
        public Boolean hasDateShift = false;
        public Boolean isDateShiftOnly = false;
    }
}n
