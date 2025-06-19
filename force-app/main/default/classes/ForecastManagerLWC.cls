public with sharing class ForecastManagerLWC {
    
    /**
     * Check if current user has admin access
     */
    @AuraEnabled
    public static Boolean checkAdminAccess() {
        return ForecastUtilityService.checkAdminAccess();
    }
    
    /**
     * Get current forecast month
     */
    @AuraEnabled
    public static String getCurrentForecastMonth() {
        return ForecastUtilityService.getCurrentForecastMonth();
    }
    
    /**
     * Get complete dashboard data including historical and forward pipeline
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDashboardData() {
        return ForecastDataService.getDashboardData();
    }
    
    /**
     * Get opportunity changes data
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getOpportunityChanges() {
        return ForecastDataService.getOpportunityChanges();
    }
    
    /**
     * Advance forecast to next month
     */
    @AuraEnabled
    public static Map<String, String> advanceToNextMonth() {
        return ForecastMonthService.advanceToNextMonth();
    }
    
    /**
     * Synchronize all snapshots to target month
     */
    @AuraEnabled
    public static void synchronizeAllSnapshotsToCurrentMonth(String targetMonth) {
        ForecastMonthService.synchronizeAllSnapshotsToCurrentMonth(targetMonth);
    }
    
    /**
     * Generate complete simulation data
     */
    @AuraEnabled
    public static Map<String, Object> generateSimulationData() {
        return ForecastSimulationService.generateSimulationData();
    }
    
    /**
     * Reset all data to January 2025
     */
    @AuraEnabled
    public static Map<String, Object> resetToJanuary2025() {
        return ForecastSimulationService.resetToJanuary2025();
    }
    
    /**
     * Clean up simulation data (alias for reset)
     */
    @AuraEnabled
    public static Map<String, Object> cleanupSimulationData() {
        return ForecastSimulationService.resetToJanuary2025();
    }
}