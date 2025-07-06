public class OpportunitySnapshotHandler {
    
    public static void createOpportunitySnapshots(List<Opportunity> opportunities) {
        List<Opty_Sd__c> snapshotsToInsert = new List<Opty_Sd__c>();
        String currentMonth = ForecastMonthService.getCurrentForecastMonthOverride() != null ? 
        ForecastMonthService.getCurrentForecastMonthOverride() : 
        ForecastUtilityService.getCurrentForecastMonth();
        for (Opportunity opty : opportunities) {
            // Skip if required fields are missing
            if (opty.CloseDate == null || opty.Amount == null || 
                opty.Probability == null || opty.Period_of_Performance__c == null) {
                continue;
            }
            
            // Calculate weighted revenue
            Decimal weightedRevenue = opty.Amount * (opty.Probability / 100);
            
            // Calculate revenue per month during performance period
            Decimal revenuePerMonth = 0;
            if (opty.Period_of_Performance__c > 0) {
                revenuePerMonth = weightedRevenue / opty.Period_of_Performance__c;
            }
            
            // Create 36 monthly snapshots starting from close date
            Date startDate = opty.CloseDate.toStartOfMonth();
            
            for (Integer i = 0; i < 36; i++) {
                Opty_Sd__c snapshot = new Opty_Sd__c();
                snapshot.Opportunity__c = opty.Id;
                snapshot.Revenue_Date__c = startDate.addMonths(i); // Fixed target date
                snapshot.Month0__c = currentMonth; // Current version month
                snapshot.CloseDate0__c = opty.CloseDate;
                
                // Apply revenue only during performance period
                if (i < opty.Period_of_Performance__c) {
                    snapshot.Amount0__c = revenuePerMonth;
                } else {
                    snapshot.Amount0__c = 0;
                }
                
                // Set initial values
                snapshot.Reason0__c = 'New';
                
                snapshotsToInsert.add(snapshot);
            }
        }
        
        if (!snapshotsToInsert.isEmpty()) {
            insert snapshotsToInsert;
        }
    }
    
    public static void updateOpportunitySnapshots(List<Opportunity> opportunities, Map<Id, Opportunity> oldOpportunityMap) {
        Set<Id> opportunityIds = new Set<Id>();
        String currentMonth = ForecastMonthService.getCurrentForecastMonthOverride() != null ? 
        ForecastMonthService.getCurrentForecastMonthOverride() : 
        ForecastUtilityService.getCurrentForecastMonth();
        
        // Check which opportunities need snapshot updates
        for (Opportunity opty : opportunities) {
            Opportunity oldOpty = oldOpportunityMap.get(opty.Id);
            
            // Check if key fields changed
            if (opty.Amount != oldOpty.Amount || 
                opty.Probability != oldOpty.Probability ||
                opty.Period_of_Performance__c != oldOpty.Period_of_Performance__c ||
                opty.CloseDate != oldOpty.CloseDate ||
                opty.StageName != oldOpty.StageName) {
                
                opportunityIds.add(opty.Id);
            }
        }
        
        if (!opportunityIds.isEmpty()) {
            // Get existing snapshots
            Map<Id, List<Opty_Sd__c>> existingSnapshotsByOpty = new Map<Id, List<Opty_Sd__c>>();
            List<Opty_Sd__c> existingSnapshots = [
                SELECT Id, Opportunity__c, Revenue_Date__c, Month0__c, Amount0__c, Reason0__c, CloseDate0__c
                FROM Opty_Sd__c 
                WHERE Opportunity__c IN :opportunityIds
                ORDER BY Opportunity__c, Revenue_Date__c
            ];
            
            // Group snapshots by opportunity
            for (Opty_Sd__c snapshot : existingSnapshots) {
                if (!existingSnapshotsByOpty.containsKey(snapshot.Opportunity__c)) {
                    existingSnapshotsByOpty.put(snapshot.Opportunity__c, new List<Opty_Sd__c>());
                }
                existingSnapshotsByOpty.get(snapshot.Opportunity__c).add(snapshot);
            }
            
            // Get updated opportunity records
            List<Opportunity> updatedOpportunities = [
                SELECT Id, Amount, Probability, Period_of_Performance__c, CloseDate, StageName
                FROM Opportunity 
                WHERE Id IN :opportunityIds
            ];
            
            // Update existing snapshots
            List<Opty_Sd__c> snapshotsToUpdate = new List<Opty_Sd__c>();
            List<Opty_Sd__c> snapshotsToInsert = new List<Opty_Sd__c>();
            
            for (Opportunity opty : updatedOpportunities) {
                // Calculate new weighted revenue
                Decimal weightedRevenue = opty.Amount * (opty.Probability / 100);
                
                // Calculate new revenue per month during performance period
                Decimal revenuePerMonth = 0;
                if (opty.Period_of_Performance__c > 0) {
                    revenuePerMonth = weightedRevenue / opty.Period_of_Performance__c;
                }
                
                // Get existing snapshots for this opportunity
                List<Opty_Sd__c> existingForThisOpty = existingSnapshotsByOpty.get(opty.Id);
                Date startDate = opty.CloseDate.toStartOfMonth();
                
                if (existingForThisOpty != null && !existingForThisOpty.isEmpty()) {
                    // Update existing snapshots based on new close date and POP
                    for (Opty_Sd__c snapshot : existingForThisOpty) {
                        // Update Month0__c to current month
                        snapshot.Month0__c = currentMonth;
                        
                        // Calculate if this revenue date falls within the new performance period
                        Date newStartDate = opty.CloseDate.toStartOfMonth();
                        Date newEndDate = newStartDate.addMonths(Integer.valueOf(opty.Period_of_Performance__c) - 1);
                        
                        // Check if this snapshot's revenue date is within the new performance period
                        Date snapshotRevenueDate = snapshot.Revenue_Date__c.toStartOfMonth();
                        
                        if (snapshotRevenueDate >= newStartDate && snapshotRevenueDate <= newEndDate) {
                            // This snapshot falls within the new performance period
                            snapshot.Amount0__c = revenuePerMonth;
                        } else {
                            // This snapshot is outside the new performance period
                            snapshot.Amount0__c = 0;
                        }
                        
                        // Update reason
                        snapshot.Reason0__c = 'Updated';
                        
                        snapshotsToUpdate.add(snapshot);
                    }
                    
                    // If we need more than 36 snapshots or less than existing, handle the difference
                    Integer existingCount = existingForThisOpty.size();
                    
                    // Create additional snapshots if needed (up to 36 total)
                    if (existingCount < 36) {
                        for (Integer i = existingCount; i < 36; i++) {
                            Opty_Sd__c newSnapshot = new Opty_Sd__c();
                            newSnapshot.Opportunity__c = opty.Id;
                            newSnapshot.Revenue_Date__c = startDate.addMonths(i);
newSnapshot.Month0__c = currentMonth;
                            
                            // Apply revenue only during performance period
                            if (i < opty.Period_of_Performance__c) {
                                newSnapshot.Amount0__c = revenuePerMonth;
                            } else {
                                newSnapshot.Amount0__c = 0;
                            }
                            
                            newSnapshot.Reason0__c = 'Updated';
                            snapshotsToInsert.add(newSnapshot);
                        }
                    }
                } else {
                    // No existing snapshots, create new ones (fallback to create method logic)
                    for (Integer i = 0; i < 36; i++) {
                        Opty_Sd__c snapshot = new Opty_Sd__c();
                        snapshot.Opportunity__c = opty.Id;
                        snapshot.Revenue_Date__c = startDate.addMonths(i);
snapshot.Month0__c = currentMonth;
                        
                        // Apply revenue only during performance period
                        if (i < opty.Period_of_Performance__c) {
                            snapshot.Amount0__c = revenuePerMonth;
                        } else {
                            snapshot.Amount0__c = 0;
                        }
                        
                        snapshot.Reason0__c = 'Updated';
                        snapshotsToInsert.add(snapshot);
                    }
                }
            }
            
            // Perform DML operations
            if (!snapshotsToUpdate.isEmpty()) {
                update snapshotsToUpdate;
            }
            
            if (!snapshotsToInsert.isEmpty()) {
                insert snapshotsToInsert;
            }
        }
    }
    
    // Method to recalculate all snapshots for specific opportunities
    public static void recalculateSnapshots(Set<Id> opportunityIds) {
        // Delete existing snapshots
        List<Opty_Sd__c> existingSnapshots = [
            SELECT Id FROM Opty_Sd__c 
            WHERE Opportunity__c IN :opportunityIds
        ];
        
        if (!existingSnapshots.isEmpty()) {
            delete existingSnapshots;
        }
        
        // Get opportunity records
        List<Opportunity> opportunities = [
            SELECT Id, Amount, Probability, Period_of_Performance__c, CloseDate, StageName
            FROM Opportunity 
            WHERE Id IN :opportunityIds
        ];
        
        // Create new snapshots
        createOpportunitySnapshots(opportunities);
    }
}