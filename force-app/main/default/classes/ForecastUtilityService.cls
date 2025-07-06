public with sharing class ForecastUtilityService {
    
    /**
     * Check if current user has admin access
     */
    public static Boolean checkAdminAccess() {
        try {
            Profile userProfile = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
            return userProfile.Name == 'System Administrator';
        } catch (Exception e) {
            System.debug('Error checking admin access: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * Get current forecast month from snapshots
     */
    public static String getCurrentForecastMonth() {
        try {
            // First check if there's an overriden from ForecastMonthService
            String overriden = ForecastMonthService.getCurrentForecastMonthoverride();
            if (String.isNotBlank(overriden)) {
                return overriden;
            }
            
            // Get all unique Month0__c values
            List<AggregateResult> monthResults = [
                SELECT Month0__c 
                FROM Opty_Sd__c 
                WHERE Month0__c != null 
                GROUP BY Month0__c
            ];
            
            if (monthResults.isEmpty()) {
                return '1/1/2025';
            }
            
            // Parse all months and find the latest
            Date latestDate = null;
            String latestMonthStr = null;
            
            for (AggregateResult result : monthResults) {
                String monthStr = (String)result.get('Month0__c');
                if (String.isNotBlank(monthStr)) {
                    try {
                        Date monthDate = parseDateString(monthStr);
                        if (latestDate == null || monthDate > latestDate) {
                            latestDate = monthDate;
                            latestMonthStr = monthStr;
                        }
                    } catch (Exception e) {
                        System.debug('Error parsing month string: ' + monthStr);
                    }
                }
            }
            
            return latestMonthStr != null ? latestMonthStr : '1/1/2025';
            
        } catch (Exception e) {
            System.debug('Error getting current forecast month: ' + e.getMessage());
            return '1/1/2025';
        }
    }
    
    /**
     * Format date as M/d/yyyy string
     */
    public static String formatDateString(Date dateValue) {
        if (dateValue == null) return null;
        return dateValue.month() + '/' + dateValue.day() + '/' + dateValue.year();
    }
    
    /**
     * Parse date string in M/d/yyyy format
     */
    public static Date parseDateString(String dateStr) {
        try {
            return Date.parse(dateStr);
        } catch (Exception e) {
            System.debug('Error parsing date string: ' + dateStr + ' - ' + e.getMessage());
            return Date.newInstance(2025, 1, 1);
        }
    }
    
    /**
     * Create short month label (Jan'25 format)
     */
    public static String createShortMonthLabel(Date dateValue) {
        if (dateValue == null) return '';
        
        List<String> monthNames = new List<String>{
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        };
        
        Integer monthIndex = dateValue.month() - 1;
        if (monthIndex < 0 || monthIndex >= 12) return '';
        
        String yearStr = String.valueOf(dateValue.year());
        return monthNames[monthIndex] + '\'' + yearStr.substring(2);
    }
    
    /**
     * Generate M/yyyy format for month labels
     */
    public static String createMonthYearLabel(Date dateValue) {
        if (dateValue == null) return '';
        return dateValue.month() + '/' + dateValue.year();
    }
    
    /**
     * Calculate total pipeline value from opportunities
     */
    public static Decimal calculateTotalPipeline(List<Opportunity> opportunities) {
        Decimal total = 0;
        if (opportunities != null) {
            for (Opportunity opp : opportunities) {
                if (opp.Amount != null) {
                    total += opp.Amount;
                }
            }
        }
        return total;
    }
    
    /**
     * Debug logging for Revenue_Date__c analysis
     */
    public static void logRevenueDateDebugInfo() {
        try {
            Integer totalSnapshots = [SELECT COUNT() FROM Opty_Sd__c];
            Integer snapshotsWithRevDate = [SELECT COUNT() FROM Opty_Sd__c WHERE Revenue_Date__c != null];
            Integer snapshotsWithoutRevDate = totalSnapshots - snapshotsWithRevDate;
            
            if (snapshotsWithoutRevDate > 0) {
                List<Opty_Sd__c> sampleNulls = [
                    SELECT Id, Name, Opportunity__r.Name, Opportunity__r.CloseDate, Amount0__c, Revenue_Date__c
                    FROM Opty_Sd__c 
                    WHERE Revenue_Date__c = null 
                    LIMIT 5
                ];
                for (Opty_Sd__c sample : sampleNulls) {
                }
            }
        } catch (Exception e) {
            System.debug('Error in debug logging: ' + e.getMessage());
        }
    }
    
    /**
     * Validate admin access and throw exception if not authorized
     */
    public static void validateAdminAccess() {
        if (!checkAdminAccess()) {
            throw new AuraHandledException('You do not have permission to perform this action.');
        }
    }
}