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
            
            List<Opportunity> opportunities = generateSimulationOpportunities(accounts);
            insert opportunities;
            
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
     * Perform complete cleanup of simulation data - handle dependencies gracefully
     */
    private static Map<String, Integer> performCompleteCleanup() {
        Integer snapshotCount = 0;
        Integer oppCount = 0;
        Integer accountCount = 0;
        
        try {
            // Delete all snapshots first
            List<Opty_Sd__c> allSnapshots = [SELECT Id FROM Opty_Sd__c];
            snapshotCount = allSnapshots.size();
            if (snapshotCount > 0) {
                delete allSnapshots;
            }
        } catch (Exception e) {
            System.debug('Warning: Could not delete some snapshots: ' + e.getMessage());
        }
        
        try {
            // Delete all opportunities
            List<Opportunity> allOpps = [SELECT Id FROM Opportunity];
            oppCount = allOpps.size();
            if (oppCount > 0) {
                delete allOpps;
            }
        } catch (Exception e) {
            System.debug('Warning: Could not delete some opportunities: ' + e.getMessage());
        }
        
        try {
            // Try to delete entitlements first to avoid dependency issues
            List<Entitlement> entitlements = [SELECT Id FROM Entitlement];
            if (entitlements.size() > 0) {
                delete entitlements;
            }
        } catch (Exception e) {
            System.debug('Warning: Could not delete entitlements: ' + e.getMessage());
        }
        
        try {
            // Delete accounts that can be deleted
            List<Account> allAccounts = [SELECT Id FROM Account];
            accountCount = allAccounts.size();
            
            if (accountCount > 0) {
                // Try to delete all accounts, but handle failures gracefully
                List<Database.DeleteResult> deleteResults = Database.delete(allAccounts, false);
                Integer successCount = 0;
                
                for (Integer i = 0; i < deleteResults.size(); i++) {
                    if (deleteResults[i].isSuccess()) {
                        successCount++;
                    } else {
                    }
                }
                
                accountCount = successCount;
            }
        } catch (Exception e) {
            System.debug('Warning: Could not delete some accounts: ' + e.getMessage());
            accountCount = 0;
        }
        
        Map<String, Integer> counts = new Map<String, Integer>();
        counts.put('snapshots', snapshotCount);
        counts.put('opportunities', oppCount);
        counts.put('accounts', accountCount);
        
        return counts;
    }
    
    /**
     * Generate simulation accounts without SIM prefix
     */
    private static List<Account> generateSimulationAccounts() {
        List<String> companyNames = new List<String>{
            'Acme Corporation', 'Global Systems Inc', 'Tech Solutions Ltd', 'Innovation Labs',
            'Data Dynamics Corp', 'CloudFirst Technologies', 'Digital Ventures LLC', 'Smart Analytics Inc',
            'Future Works Group', 'NextGen Technologies', 'Alpha Industries', 'Beta Solutions',
            'Gamma Corporation', 'Delta Systems Inc', 'Epsilon Group', 'Zeta Enterprises',
            'Eta Technologies', 'Theta Solutions', 'Iota Innovations', 'Kappa Corporation',
            'Lambda Systems', 'Mu Dynamics', 'Nu Technologies', 'Xi Solutions',
            'Omicron Group', 'Pi Enterprises', 'Rho Tech', 'Sigma Corporation',
            'Tau Systems', 'Upsilon Group'
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
                Name = productType + ' - ' + account.Name + ' - 2025-' + String.valueOf(i + 1),
                AccountId = account.Id,
                Amount = monthlyRevenue * periodMonths,
                CloseDate = closeDate,
                StageName = stage,
                Probability = probability,
                LeadSource = 'Web',
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