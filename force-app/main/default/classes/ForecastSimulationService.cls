public with sharing class ForecastSimulationService {
    
    /**
     * Generate complete simulation data
     */
    public static Map<String, Object> generateSimulationData() {
        try {
            ForecastUtilityService.validateAdminAccess();
            
            // Step 1: Complete cleanup
            Map<String, Integer> deletionCounts = performCompleteCleanup();
            
            // Step 2: Generate fresh data
            List<Account> accounts = generateSimulationAccounts();
            insert accounts;
            System.debug('Created ' + accounts.size() + ' new accounts');
            
            List<Opportunity> opportunities = generateSimulationOpportunities(accounts);
            insert opportunities;
            System.debug('Created ' + opportunities.size() + ' new opportunities');
            
           ForecastMonthService.synchronizeAllSnapshotsToCurrentMonth('1/1/2025');
            
            // Build result
            Map<String, Object> result = new Map<String, Object>();
            result.put('accountsCreated', accounts.size());
            result.put('opportunitiesCreated', opportunities.size());
            result.put('totalPipelineValue', ForecastUtilityService.calculateTotalPipeline(opportunities));
            result.put('currentForecastMonth', '1/1/2025');
            result.put('accountsDeleted', deletionCounts.get('accounts'));
            result.put('opportunitiesDeleted', deletionCounts.get('opportunities'));
            result.put('snapshotsDeleted', deletionCounts.get('snapshots'));
            
            return result;
            
        } catch (Exception e) {
            System.debug('Error generating simulation data: ' + e.getMessage());
            throw new AuraHandledException('Error generating simulation data: ' + e.getMessage());
        }
    }
    
    /**
     * Reset all simulation data
     */
    public static Map<String, Object> resetToJanuary2025() {
        try {
            ForecastUtilityService.validateAdminAccess();
            
            Map<String, Integer> deletionCounts = performCompleteCleanup();
            
            Map<String, Object> result = new Map<String, Object>();
            result.put('opportunitiesDeleted', deletionCounts.get('opportunities'));
            result.put('accountsDeleted', deletionCounts.get('accounts'));
            result.put('snapshotsDeleted', deletionCounts.get('snapshots'));
            result.put('resetDate', '1/1/2025');
            
            return result;
            
        } catch (Exception e) {
            System.debug('Error resetting simulation data: ' + e.getMessage());
            throw new AuraHandledException('Error resetting simulation data: ' + e.getMessage());
        }
    }
    
    /**
     * Perform complete cleanup of simulation data
     */
    private static Map<String, Integer> performCompleteCleanup() {
        // Delete all snapshots
        List<Opty_Sd__c> allSnapshots = [SELECT Id FROM Opty_Sd__c];
        Integer snapshotCount = allSnapshots.size();
        delete allSnapshots;
        System.debug('Deleted ' + snapshotCount + ' existing snapshots');
        
        // Delete simulation opportunities
        List<Opportunity> simOpps = [SELECT Id FROM Opportunity WHERE Name LIKE 'SIM-%'];
        Integer oppCount = simOpps.size();
        delete simOpps;
        System.debug('Deleted ' + oppCount + ' existing SIM opportunities');
        
        // Delete simulation accounts
        List<Account> simAccounts = [SELECT Id FROM Account WHERE Name LIKE 'SIM_%' AND Industry = 'Technology'];
        Integer accountCount = simAccounts.size();
        delete simAccounts;
        System.debug('Deleted ' + accountCount + ' existing SIM accounts');
        
        Map<String, Integer> counts = new Map<String, Integer>();
        counts.put('snapshots', snapshotCount);
        counts.put('opportunities', oppCount);
        counts.put('accounts', accountCount);
        
        return counts;
    }
    
    /**
     * Generate simulation accounts
     */
    private static List<Account> generateSimulationAccounts() {
        List<String> companyNames = new List<String>{
            'SIM_Acme Corp', 'SIM_Global Systems', 'SIM_Tech Solutions', 'SIM_Innovation Labs',
            'SIM_Data Dynamics', 'SIM_Cloud First', 'SIM_Digital Ventures', 'SIM_Smart Analytics',
            'SIM_Future Works', 'SIM_NextGen Tech', 'SIM_Alpha Industries', 'SIM_Beta Solutions',
            'SIM_Gamma Corp', 'SIM_Delta Systems', 'SIM_Epsilon Group', 'SIM_Zeta Enterprises',
            'SIM_Eta Technologies', 'SIM_Theta Solutions', 'SIM_Iota Innovations', 'SIM_Kappa Corp',
            'SIM_Lambda Systems', 'SIM_Mu Dynamics', 'SIM_Nu Technologies', 'SIM_Xi Solutions',
            'SIM_Omicron Group', 'SIM_Pi Enterprises', 'SIM_Rho Tech', 'SIM_Sigma Corp',
            'SIM_Tau Systems', 'SIM_Upsilon Group'
        };
        
        List<Account> accounts = new List<Account>();
        for (String name : companyNames) {
            accounts.add(new Account(
                Name = name,
                Type = 'Customer',
                Industry = 'Technology'
            ));
        }
        return accounts;
    }
    
    /**
     * Generate simulation opportunities
     */
/**
 * Generate simulation opportunities with simplified close date logic
 */
private static List<Opportunity> generateSimulationOpportunities(List<Account> accounts) {
    List<String> stages = new List<String>{
        'Prospecting', 'Qualification', 'Needs Analysis', 'Value Proposition',
        'Id. Decision Makers', 'Proposal/Price Quote', 'Negotiation/Review'
    };
    
    List<String> productTypes = new List<String>{
        'Software License', 'Consulting Services', 'Support Package',
        'Training Program', 'Implementation Services', 'Maintenance Contract'
    };
    
    // Adjusted periods for better revenue distribution - shorter contracts
    List<Integer> periods = new List<Integer>{1, 2, 3, 6, 6, 12, 12, 18, 24, 36};
    
    // Higher revenue amounts for better pipeline visibility
    List<Integer> revenues = new List<Integer>{15000, 25000, 35000, 45000, 55000, 75000};
    
    List<Opportunity> opportunities = new List<Opportunity>();
    
    for (Integer i = 0; i < 40; i++) { // Increased from 30 to 40 opportunities
        Account account = accounts[Math.mod(i, accounts.size())];
        String stage = stages[Math.mod(i, stages.size())];
        String productType = productTypes[Math.mod(i, productTypes.size())];
        Integer periodMonths = periods[Math.mod(i, periods.size())];
        Integer monthlyRevenue = revenues[Math.mod(i, revenues.size())];
        
        // SIMPLIFIED: Generate close date with weighted month selection
        Date closeDate = generateSimpleCloseDate();
        
        Integer probability = getProbabilityByStage(stage);
        
        opportunities.add(new Opportunity(
            Name = 'SIM-' + productType + ' - ' + account.Name + ' - 2025-' + String.valueOf(i + 1),
            AccountId = account.Id,
            Amount = monthlyRevenue * periodMonths,
            CloseDate = closeDate,
            StageName = stage,
            Probability = probability,
            LeadSource = 'Simulation',
            Description = periodMonths + '-month ' + productType.toLowerCase() + ' engagement. Monthly: $' + String.valueOf(monthlyRevenue),
            Type = 'New Customer',
            Period_of_Performance__c = periodMonths
        ));
    }
    
    return opportunities;
}
/**
 * Generate simple close date: All day 1, year 2025, weighted month
 */
private static Date generateSimpleCloseDate() {
    // Get random value 0-99
    Integer randomValue = Math.mod(Math.abs(Crypto.getRandomInteger()), 100);
    
    Integer month;
    if (randomValue < 75) {
        // 75% chance: Months 1-6 (Jan-Jun)
        month = Math.mod(Math.abs(Crypto.getRandomInteger()), 6) + 1; // 1-6
    } else if (randomValue < 90) {
        // 15% chance: Months 7-9 (Jul-Sep)
        month = Math.mod(Math.abs(Crypto.getRandomInteger()), 3) + 7; // 7-9
    } else {
        // 10% chance: Months 10-12 (Oct-Dec)
        month = Math.mod(Math.abs(Crypto.getRandomInteger()), 3) + 10; // 10-12
    }
    
    // All opportunities close on the 1st of their month in 2025
    return Date.newInstance(2025, month, 1);
}
    
    /**
     * Get probability by stage name
     */
    private static Integer getProbabilityByStage(String stage) {
        if (stage == 'Prospecting') return 10;
        else if (stage == 'Qualification') return 20;
        else if (stage == 'Needs Analysis') return 30;
        else if (stage == 'Value Proposition') return 40;
        else if (stage == 'Id. Decision Makers') return 60;
        else if (stage == 'Proposal/Price Quote') return 75;
        else if (stage == 'Negotiation/Review') return 90;
        else return 50; // Default
    }
    /**
 * Calculate revenue recognition date - biased toward 2025
 */
private static Date calculateRevenueDate(Date startDate, Integer periodMonths) {
    // For shorter contracts (<=6 months), revenue date = start date + 1-3 months
    if (periodMonths <= 6) {
        Integer revenueDelay = Math.mod(Math.abs(Crypto.getRandomInteger()), 3) + 1; // 1-3 months
        return startDate.addMonths(revenueDelay);
    }
    
    // For longer contracts, spread revenue recognition across 2025-2026
    // But favor 2025 dates
    Integer randomDelay = Math.mod(Math.abs(Crypto.getRandomInteger()), 100);
    Integer revenueDelay;
    
    if (randomDelay < 60) {
        // 60% chance: Revenue in 2025 (1-8 months from start)
        revenueDelay = Math.mod(Math.abs(Crypto.getRandomInteger()), 8) + 1;
    } else {
        // 40% chance: Revenue in 2026 (9-18 months from start)
        revenueDelay = Math.mod(Math.abs(Crypto.getRandomInteger()), 10) + 9;
    }
    
    return startDate.addMonths(revenueDelay);
}
}