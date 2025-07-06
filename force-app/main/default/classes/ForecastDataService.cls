public with sharing class ForecastDataService {
    /**
     * Get annual revenue data for a specific year
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAnnualRevenueData(Integer year) {
        try {
            Map<String, Object> annualData = new Map<String, Object>();
            
            // Calculate date range for the year
            Date startDate = Date.newInstance(year, 1, 1);
            Date endDate = Date.newInstance(year + 1, 1, 1);
            
            // Create monthly amounts array (12 months)
            List<Decimal> monthlyAmounts = new List<Decimal>();
            List<String> monthLabels = new List<String>();
            String[] monthNames = new String[]{'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                                             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'};
            
            // Initialize arrays with zeros
            for (Integer i = 1; i <= 12; i++) {
                monthlyAmounts.add(0);
                monthLabels.add(monthNames[i-1] + ' ' + year);
            }
            
            // Query all snapshots for the year
            List<Opty_Sd__c> snapshots = [
                SELECT Revenue_Date__c, Amount0__c
                FROM Opty_Sd__c 
                WHERE Revenue_Date__c != null 
                AND Amount0__c != null
                AND Revenue_Date__c >= :startDate
                AND Revenue_Date__c < :endDate
            ];
            
            // Aggregate by month
            for (Opty_Sd__c snapshot : snapshots) {
                Integer monthIndex = snapshot.Revenue_Date__c.month() - 1; // 0-based index
                if (monthIndex >= 0 && monthIndex < 12) {
                    monthlyAmounts[monthIndex] += snapshot.Amount0__c;
                }
            }
            
            // Calculate total
            Decimal totalAnnual = 0;
            for (Decimal amount : monthlyAmounts) {
                totalAnnual += amount;
            }
            
            // Return structured data
            annualData.put('year', year);
            annualData.put('monthLabels', monthLabels);
            annualData.put('monthlyAmounts', monthlyAmounts);
            annualData.put('totalAnnual', totalAnnual);
            
            return annualData;
            
        } catch (Exception e) {
            System.debug('Error in getAnnualRevenueData: ' + e.getMessage());
            // Return empty structure on error
            Map<String, Object> emptyData = new Map<String, Object>();
            emptyData.put('year', year);
            emptyData.put('monthLabels', new List<String>());
            emptyData.put('monthlyAmounts', new List<Decimal>());
            emptyData.put('totalAnnual', 0);
            return emptyData;
        }
    }
    
    /**
     * Get dashboard data including historical and forward pipeline
     */
    public static Map<String, Object> getDashboardData() {
        try {
            Map<String, Object> dashboardData = new Map<String, Object>();
            
            // Get historical pipeline totals
            Map<String, Object> historicalData = getHistoricalPipelineData();
            dashboardData.putAll(historicalData);
            
            // Get counts
            Map<String, Object> countData = getCountData();
            dashboardData.putAll(countData);
            
            // Get forward pipeline
            Map<String, Object> forwardPipeline = getForwardPipelineData();
            dashboardData.put('forwardPipeline', forwardPipeline);
            
            return dashboardData;
            
        } catch (Exception e) {
            throw new AuraHandledException('Unable to retrieve dashboard data: ' + e.getMessage());
        }
    }
    
    /**
     * Get historical pipeline data (last 6 months)
     */
    private static Map<String, Object> getHistoricalPipelineData() {
        Map<String, Object> historicalData = new Map<String, Object>();
        
        List<AggregateResult> pipelineByMonth = [
            SELECT 
                SUM(Amount0__c) total0,
                SUM(Amount1__c) total1,
                SUM(Amount2__c) total2,
                SUM(Amount3__c) total3,
                SUM(Amount4__c) total4,
                SUM(Amount5__c) total5
            FROM Opty_Sd__c
            WHERE Amount0__c != null
        ];
        
        if (!pipelineByMonth.isEmpty()) {
            AggregateResult result = pipelineByMonth[0];
            historicalData.put('currentMonth', result.get('total0') != null ? result.get('total0') : 0);
            historicalData.put('previousMonth1', result.get('total1') != null ? result.get('total1') : 0);
            historicalData.put('previousMonth2', result.get('total2') != null ? result.get('total2') : 0);
            historicalData.put('previousMonth3', result.get('total3') != null ? result.get('total3') : 0);
            historicalData.put('previousMonth4', result.get('total4') != null ? result.get('total4') : 0);
            historicalData.put('previousMonth5', result.get('total5') != null ? result.get('total5') : 0);
        } else {
            historicalData.put('currentMonth', 0);
            historicalData.put('previousMonth1', 0);
            historicalData.put('previousMonth2', 0);
            historicalData.put('previousMonth3', 0);
            historicalData.put('previousMonth4', 0);
            historicalData.put('previousMonth5', 0);
        }
        
        return historicalData;
    }
    
    /**
     * Get count data (opportunities and snapshots)
     */
    private static Map<String, Object> getCountData() {
        Map<String, Object> countData = new Map<String, Object>();
        
        Integer totalOpportunities = [SELECT COUNT() FROM Opportunity];
        countData.put('totalOpportunities', totalOpportunities);
        
        Integer totalSnapshots = [SELECT COUNT() FROM Opty_Sd__c];
        countData.put('totalSnapshots', totalSnapshots);
        
        return countData;
    }
    
    /**
     * Get 12-month forward pipeline data - FIXED
     */
    public static Map<String, Object> getForwardPipelineData() {
        try {
            Map<String, Object> forwardData = new Map<String, Object>();
            
            // Get current forecast month
            String currentMonthStr = ForecastUtilityService.getCurrentForecastMonth();
            Date currentMonth = ForecastUtilityService.parseDateString(currentMonthStr);
            
            // Calculate 12 future months
            List<Date> futureMonths = new List<Date>();
            List<String> monthLabels = new List<String>();
            List<Decimal> monthlyAmounts = new List<Decimal>();
            
            // Initialize arrays
            for (Integer i = 0; i < 12; i++) {
                Date targetMonth = currentMonth.addMonths(i);
                futureMonths.add(targetMonth);
                monthLabels.add(ForecastUtilityService.createMonthYearLabel(targetMonth));
                monthlyAmounts.add(0); // Initialize with zeros
            }
            
            // Query all forward pipeline snapshots
            Date endDate = currentMonth.addMonths(12);
            List<Opty_Sd__c> snapshots = [
                SELECT Revenue_Date__c, Amount0__c
                FROM Opty_Sd__c 
                WHERE Revenue_Date__c != null 
                AND Amount0__c != null
                AND Revenue_Date__c >= :currentMonth
                AND Revenue_Date__c < :endDate
            ];
            
            // Aggregate by month
            for (Opty_Sd__c snapshot : snapshots) {
                // Calculate which month index this belongs to
                Integer monthsDiff = currentMonth.monthsBetween(snapshot.Revenue_Date__c);
                
                if (monthsDiff >= 0 && monthsDiff < 12) {
                    monthlyAmounts[monthsDiff] += snapshot.Amount0__c;
                }
            }
            
            // Calculate total
            Decimal totalForward = 0;
            for (Decimal amount : monthlyAmounts) {
                totalForward += amount;
            }
            
            // Return structured data
            forwardData.put('monthLabels', monthLabels);
            forwardData.put('monthlyAmounts', monthlyAmounts);
            forwardData.put('totalForward', totalForward);
            
            return forwardData;
            
        } catch (Exception e) {
            System.debug('Error in getForwardPipelineData: ' + e.getMessage());
            // Return empty structure on error
            Map<String, Object> emptyData = new Map<String, Object>();
            emptyData.put('monthLabels', new List<String>());
            emptyData.put('monthlyAmounts', new List<Decimal>());
            emptyData.put('totalForward', 0);
            return emptyData;
        }
    }
    
    /**
     * Get opportunity changes data
     */
    public static List<Map<String, Object>> getOpportunityChanges() {
        try {
            List<Map<String, Object>> changes = new List<Map<String, Object>>();
            
            // Get snapshots with opportunity details
            List<Opty_Sd__c> snapshots = [
                SELECT Id, Amount0__c, Amount1__c, Reason0__c, Month0__c, Month1__c,
                       Opportunity__r.Name, Opportunity__r.StageName, Opportunity__r.Amount
                FROM Opty_Sd__c 
                WHERE Opportunity__c != null 
                AND Amount0__c != null 
                AND Amount1__c != null
                LIMIT 20
            ];
            
            // Sort by absolute delta amount (largest changes first)
            List<OpportunityChangeWrapper> wrappedChanges = new List<OpportunityChangeWrapper>();
            
            for (Opty_Sd__c snapshot : snapshots) {
                Decimal currentAmount = snapshot.Amount0__c != null ? snapshot.Amount0__c : 0;
                Decimal previousAmount = snapshot.Amount1__c != null ? snapshot.Amount1__c : 0;
                Decimal deltaAmount = currentAmount - previousAmount;
                
                // Only include opportunities with significant changes (>$1K)
                if (Math.abs(deltaAmount) >= 1000) {
                    OpportunityChangeWrapper wrapper = new OpportunityChangeWrapper();
                    wrapper.snapshot = snapshot;
                    wrapper.deltaAmount = deltaAmount;
                    wrapper.absDeltaAmount = Math.abs(deltaAmount);
                    wrappedChanges.add(wrapper);
                }
            }
            
            // Sort by absolute delta amount (descending)
            wrappedChanges.sort();
            
            // Build result list
            for (OpportunityChangeWrapper wrapper : wrappedChanges) {
                Opty_Sd__c snapshot = wrapper.snapshot;
                Decimal currentAmount = snapshot.Amount0__c != null ? snapshot.Amount0__c : 0;
                Decimal previousAmount = snapshot.Amount1__c != null ? snapshot.Amount1__c : 0;
                Decimal deltaAmount = wrapper.deltaAmount;
                
                Map<String, Object> change = new Map<String, Object>();
                change.put('opportunityName', snapshot.Opportunity__r.Name);
                change.put('stageName', snapshot.Opportunity__r.StageName);
                change.put('currentAmount', currentAmount);
                change.put('previousAmount', previousAmount);
                change.put('deltaAmount', deltaAmount);
                change.put('reason', snapshot.Reason0__c);
                change.put('currentMonth', snapshot.Month0__c);
                change.put('previousMonth', snapshot.Month1__c);
                
                // Determine change type
                if (deltaAmount > 0) {
                    change.put('changeType', 'increase');
                    change.put('changeIcon', 'trending_up');
                } else if (deltaAmount < 0) {
                    change.put('changeType', 'decrease');
                    change.put('changeIcon', 'trending_down');
                } else {
                    change.put('changeType', 'none');
                    change.put('changeIcon', 'insert_chart');
                }
                
                changes.add(change);
            }
            
            return changes;
            
        } catch (Exception e) {
            return new List<Map<String, Object>>();
        }
    }
    
    /**
     * Helper class for sorting opportunity changes
     */
    public class OpportunityChangeWrapper implements Comparable {
        public Opty_Sd__c snapshot;
        public Decimal deltaAmount;
        public Decimal absDeltaAmount;
        
        public Integer compareTo(Object compareTo) {
            OpportunityChangeWrapper other = (OpportunityChangeWrapper)compareTo;
            if (this.absDeltaAmount > other.absDeltaAmount) return -1;
            if (this.absDeltaAmount < other.absDeltaAmount) return 1;
            return 0;
        }
    }
}