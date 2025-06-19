public with sharing class ForecastMonthService {
    
    // Track opportunity changes for reporting
    private static Map<Id, List<String>> opportunityChanges = new Map<Id, List<String>>();
    
    /**
     * Advance forecast to next month with opportunity-level simulation
     */
    public static Map<String, String> advanceToNextMonth() {
        try {
            ForecastUtilityService.validateAdminAccess();
            
            // Get current forecast month
            String currentMonthStr = ForecastUtilityService.getCurrentForecastMonth();
            Date currentForecastMonth = ForecastUtilityService.parseDateString(currentMonthStr);
            
            // Calculate next month
            Date nextMonth = currentForecastMonth.addMonths(1);
            String nextMonthString = ForecastUtilityService.formatDateString(nextMonth);
            
            // Determine market conditions (random)
            Boolean isBadMonth = Math.random() < 0.3; // 30% chance of bad month
            String monthType = isBadMonth ? 'Bad' : 'Good';
            
            System.debug('=== ADVANCING TO NEXT MONTH: ' + nextMonthString + ' ===');
            System.debug('Market Conditions: ' + monthType);
            
            // STEP 1: Shift all snapshot data first (preserve current amounts)
            Map<String, Integer> shiftResults = shiftAllSnapshotData(nextMonthString);
            
            // STEP 2: Apply opportunity changes in structured order
            Map<String, Integer> opportunityResults = processOpportunityChangesStructured(currentForecastMonth, nextMonth, isBadMonth);
            
            // STEP 3: Recalculate snapshot amounts based on changed opportunities
            Map<String, Integer> recalcResults = recalculateSnapshotAmounts(nextMonthString);
            
            // Return success info
            Map<String, String> result = new Map<String, String>();
            result.put('success', 'true');
            result.put('newMonth', nextMonthString);
            result.put('recordsUpdated', String.valueOf(shiftResults.get('recordsUpdated')));
            result.put('changedOpportunities', String.valueOf(opportunityResults.get('totalChanged')));
            result.put('wonOpportunities', String.valueOf(opportunityResults.get('wonCount')));
            result.put('lostOpportunities', String.valueOf(opportunityResults.get('lostCount')));
            result.put('monthType', monthType);
            
            return result;
            
        } catch (Exception e) {
            System.debug('Error advancing to next month: ' + e.getMessage());
            throw new AuraHandledException('Error advancing to next month: ' + e.getMessage());
        }
    }
    
    /**
     * Process opportunity changes in structured order
     */
    private static Map<String, Integer> processOpportunityChangesStructured(Date currentForecastMonth, Date nextMonth, Boolean isBadMonth) {
        // Get all opportunities that could be modified
        List<Opportunity> opportunities = [
            SELECT Id, Name, StageName, Amount, CloseDate, Probability, 
                   CreatedDate, LastModifiedDate, LeadSource, Period_of_Performance__c
            FROM Opportunity 
            WHERE (StageName NOT IN ('Closed Won', 'Closed Lost'))
            OR (CloseDate < TODAY AND StageName NOT IN ('Closed Won', 'Closed Lost'))
            ORDER BY CloseDate, CreatedDate
        ];
                
        // Clear change tracking
        opportunityChanges.clear();
        
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        Integer totalProcessed = 0;
        Integer totalChanged = 0;
        Integer wonCount = 0;
        Integer lostCount = 0;
        
        for (Opportunity opp : opportunities) {
            totalProcessed++;
            Boolean wasChanged = false;
        
            // Initialize change tracking for this opportunity
            opportunityChanges.put(opp.Id, new List<String>());
            
            // 1. CURRENT CLOSE MONTH - Won/Lost/Date Shift (BEFORE overdue processing)
            wasChanged = processCurrentCloseMonth(opp, currentForecastMonth, isBadMonth) || wasChanged;
            // 2. OVERDUE OPPORTUNITIES - Fix dates AFTER trying to close (only if still open)
            if (opp.StageName != 'Closed Won' && opp.StageName != 'Closed Lost') {
                wasChanged = processOverdueOpportunities(opp, nextMonth) || wasChanged;
            }
            
            // 3. STAGE CHANGES (for non-closed opportunities)
            if (opp.StageName != 'Closed Won' && opp.StageName != 'Closed Lost') {
                wasChanged = processStageChanges(opp, isBadMonth) || wasChanged;
            }
            
            // 4. NON-CURRENT MONTH DATE CHANGES
            if (opp.StageName != 'Closed Won' && opp.StageName != 'Closed Lost') {
                wasChanged = processDateChanges(opp, nextMonth, isBadMonth) || wasChanged;
            }
            
            // 5. AMOUNT CHANGES
            if (opp.StageName != 'Closed Won' && opp.StageName != 'Closed Lost') {
                wasChanged = processAmountChanges(opp, isBadMonth) || wasChanged;
            }
            
            // 6. POP CHANGES
            if (opp.StageName != 'Closed Won' && opp.StageName != 'Closed Lost') {
                wasChanged = processPOPChanges(opp, isBadMonth) || wasChanged;
            }
            // Count closures
            if (opp.StageName == 'Closed Won') wonCount++;
            if (opp.StageName == 'Closed Lost') lostCount++;
            
            if (wasChanged) {
                opportunitiesToUpdate.add(opp);
                totalChanged++;
                
                System.debug('CHANGED: Stage=' + opp.StageName + ', Close=' + opp.CloseDate + ', Amount=' + opp.Amount + ', POP=' + opp.Period_of_Performance__c);
                System.debug('Changes: ' + String.join(opportunityChanges.get(opp.Id), ', '));
            } else {
                System.debug('NO CHANGES');
            }
        }
        
        // Update opportunities
        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
            System.debug('=== UPDATED ' + opportunitiesToUpdate.size() + ' OPPORTUNITIES ===');
        }
        
        Map<String, Integer> results = new Map<String, Integer>();
        results.put('totalProcessed', totalProcessed);
        results.put('totalChanged', totalChanged);
        results.put('wonCount', wonCount);
        results.put('lostCount', lostCount);
        
        return results;
    }
    
    /**
     * 0. OVERDUE OPPORTUNITIES - Update close dates for overdue open opportunities
     */
    private static Boolean processOverdueOpportunities(Opportunity opp, Date nextMonth) {
        // Skip if already closed
        if (opp.StageName == 'Closed Won' || opp.StageName == 'Closed Lost') {
            return false;
        }
        
        // Check if opportunity is overdue (close date is before current forecast month)
        if (opp.CloseDate == null) {
            return false;
        }
        
        // Convert dates to integers for comparison (YYYY * 12 + MM)
        Integer oppCloseInt = opp.CloseDate.year() * 12 + opp.CloseDate.month();
        Integer currentMonthInt = nextMonth.year() * 12 + nextMonth.month();
        
        if (oppCloseInt < currentMonthInt) {
            // Opportunity is overdue - push close date forward by 1-6 months from current month
            Integer pushMonths = (Integer)(Math.random() * 6) + 1; // 1-6 months
            Date oldDate = opp.CloseDate;
            opp.CloseDate = nextMonth.addMonths(pushMonths);         
            opportunityChanges.get(opp.Id).add('Overdue fix: ' + oldDate + ' -> ' + opp.CloseDate);
            return true;
        }
        
        return false; // Not overdue
    }
    
    /**
     * 1. CURRENT CLOSE MONTH - Handle Won/Lost/Date Shifts
     */
    private static Boolean processCurrentCloseMonth(Opportunity opp, Date currentForecastMonth, Boolean isBadMonth) {
      
if (opp.CloseDate != null && 
   opp.CloseDate.year() == currentForecastMonth.year() && 
   opp.CloseDate.month() == currentForecastMonth.month()) {

        
        Double randomValue = Math.random();
        
     
        if (isBadMonth) {
            // Bad month: 30% won, 70% lost, 0% date shift
            if (randomValue < 0.30) {
                return closeOpportunityWon(opp, currentForecastMonth);
            } else if (randomValue >= 0.30) {
                return closeOpportunityLost(opp, currentForecastMonth);
            } else if (randomValue < 1) {
                return shiftCloseDateForward(opp, 'Bad month delay');
            }
        } else {
            // Good month: 70% won, 30% lost, 0% date shift
            if (randomValue >= 0.30) {
                return closeOpportunityWon(opp, currentForecastMonth);
            } else if (randomValue < 0.30) {
                return closeOpportunityLost(opp, currentForecastMonth);
            } else if (randomValue < 1) {
                return shiftCloseDateForward(opp, 'Schedule adjustment');
            }
        }
      }

        return false; // No change
    }
    
    /**
     * 2. STAGE CHANGES - Move stages forward/backward
     */
    private static Boolean processStageChanges(Opportunity opp, Boolean isBadMonth) {
        Double randomValue = Math.random();
        
        if (isBadMonth) {
            // Bad month: 15% backward, 5% forward
            if (randomValue < 0.15) {
                return moveStageBackward(opp);
            } else if (randomValue < 0.20) {
                return moveStageForward(opp);
            }
        } else {
            // Good month: 5% backward, 20% forward
            if (randomValue < 0.05) {
                return moveStageBackward(opp);
            } else if (randomValue < 0.25) {
                return moveStageForward(opp);
            }
        }
        
        return false; // No change
    }
    
    /**
     * 3. NON-CURRENT MONTH DATE CHANGES - Accelerate or delay
     */
    private static Boolean processDateChanges(Opportunity opp, Date nextMonth, Boolean isBadMonth) {
        if (isCurrentCloseMonth(opp, nextMonth)) {
            return false; // Already handled in current month processing
        }
        
        Double randomValue = Math.random();
        
        if (isBadMonth) {
            // Bad month: 15% delay
            if (randomValue < 0.15) {
                return shiftCloseDateForward(opp, 'Market conditions delay');
            }
        } else {
            // Good month: 10% accelerate
            if (randomValue < 0.10) {
                return accelerateCloseDate(opp);
            }
        }
        
        return false; // No change
    }
    
    /**
     * 4. AMOUNT CHANGES - Increase or decrease amounts
     */
    private static Boolean processAmountChanges(Opportunity opp, Boolean isBadMonth) {
        Double randomValue = Math.random();
        
        if (isBadMonth) {
            // Bad month: 20% decrease
            if (randomValue < 0.20) {
                return decreaseAmount(opp);
            }
        } else {
            // Good month: 15% increase
            if (randomValue < 0.15) {
                return increaseAmount(opp);
            }
        }
        
        return false; // No change
    }
    
    /**
     * 5. POP CHANGES - Extend or reduce contract periods
     */
    private static Boolean processPOPChanges(Opportunity opp, Boolean isBadMonth) {
        Double randomValue = Math.random();
        
        if (isBadMonth) {
            // Bad month: 10% reduce POP
            if (randomValue < 0.10) {
                return reducePOP(opp);
            }
        } else {
            // Good month: 12% extend POP
            if (randomValue < 0.12) {
                return extendPOP(opp);
            }
        }
        
        return false; // No change
    }
    
    // =============================================================================
    // HELPER METHODS FOR SPECIFIC CHANGES
    // =============================================================================
    
    /**
     * Check if opportunity is scheduled to close in the current month
     */
    private static Boolean isCurrentCloseMonth(Opportunity opp, Date nextMonth) {
        if (opp.CloseDate == null) return false;
        
        return (opp.CloseDate.year() == nextMonth.year() && 
                opp.CloseDate.month() == nextMonth.month());
    }
    
    /**
     * Close opportunity as Won
     */
    private static Boolean closeOpportunityWon(Opportunity opp, Date nextMonth) {
        System.debug('    -> Closing as WON');
        opp.StageName = 'Closed Won';
        // Keep original close date - don't change it to nextMonth
        // opp.CloseDate stays as the original scheduled date
        opp.Probability = 100;
        opportunityChanges.get(opp.Id).add('Closed Won');
        return true;
    }
    
    /**
     * Close opportunity as Lost
     */
    private static Boolean closeOpportunityLost(Opportunity opp, Date nextMonth) {
        System.debug('    -> Closing as LOST');
        opp.StageName = 'Closed Lost';
        // Keep original close date - don't change it to nextMonth
        // opp.CloseDate stays as the original scheduled date
        opp.Probability = 0;
        opportunityChanges.get(opp.Id).add('Closed Lost');
        return true;
    }
    
    /**
     * Shift close date forward by 1-6 months
     */
    private static Boolean shiftCloseDateForward(Opportunity opp, String reason) {
        Integer pushMonths = (Integer)(Math.random() * 6) + 1; // 1-6 months
        Date oldDate = opp.CloseDate;
        opp.CloseDate = opp.CloseDate.addMonths(pushMonths);
        
        System.debug('    -> Shifting date forward: ' + oldDate + ' -> ' + opp.CloseDate + ' (+' + pushMonths + ' months)');
        opportunityChanges.get(opp.Id).add('Date shift: +' + pushMonths + ' months (' + reason + ')');
        return true;
    }
    
    /**
     * Accelerate close date by 1-3 months
     */
    private static Boolean accelerateCloseDate(Opportunity opp) {
        Integer accelerateMonths = (Integer)(Math.random() * 3) + 1; // 1-3 months
        Date newCloseDate = opp.CloseDate.addMonths(-accelerateMonths);
        
        if (newCloseDate >= Date.today()) {
            Date oldDate = opp.CloseDate;
            opp.CloseDate = newCloseDate;
            System.debug('    -> Accelerating date: ' + oldDate + ' -> ' + opp.CloseDate + ' (-' + accelerateMonths + ' months)');
            opportunityChanges.get(opp.Id).add('Date acceleration: -' + accelerateMonths + ' months');
            return true;
        } else {
            System.debug('    -> Cannot accelerate - would be in past');
            return false;
        }
    }
    
    /**
     * Move opportunity stage forward in pipeline
     */
    private static Boolean moveStageForward(Opportunity opp) {
        Map<String, String> stageProgression = new Map<String, String>{
            'Prospecting' => 'Qualification',
            'Qualification' => 'Needs Analysis',
            'Needs Analysis' => 'Value Proposition',
            'Value Proposition' => 'Id. Decision Makers',
            'Id. Decision Makers' => 'Proposal/Price Quote',
            'Proposal/Price Quote' => 'Negotiation/Review'
        };
        
        if (stageProgression.containsKey(opp.StageName)) {
            String oldStage = opp.StageName;
            opp.StageName = stageProgression.get(opp.StageName);
            opp.Probability = getProbabilityByStage(opp.StageName);
            
            System.debug('    -> Stage forward: ' + oldStage + ' -> ' + opp.StageName);
            opportunityChanges.get(opp.Id).add('Stage: ' + oldStage + ' -> ' + opp.StageName);
            return true;
        }
        
        return false;
    }
    
    /**
     * Move opportunity stage backward in pipeline
     */
    private static Boolean moveStageBackward(Opportunity opp) {
        Map<String, String> stageRegression = new Map<String, String>{
            'Negotiation/Review' => 'Proposal/Price Quote',
            'Proposal/Price Quote' => 'Id. Decision Makers',
            'Id. Decision Makers' => 'Value Proposition',
            'Value Proposition' => 'Needs Analysis',
            'Needs Analysis' => 'Qualification',
            'Qualification' => 'Prospecting'
        };
        
        if (stageRegression.containsKey(opp.StageName)) {
            String oldStage = opp.StageName;
            opp.StageName = stageRegression.get(opp.StageName);
            opp.Probability = getProbabilityByStage(opp.StageName);
            
            System.debug('    -> Stage backward: ' + oldStage + ' -> ' + opp.StageName);
            opportunityChanges.get(opp.Id).add('Stage: ' + oldStage + ' -> ' + opp.StageName);
            return true;
        }
        
        return false;
    }
    
    /**
     * Increase opportunity amount by 20-75%
     */
    private static Boolean increaseAmount(Opportunity opp) {
        Decimal increase = 0.20 + (Math.random() * 0.55); // 20-75%
        Decimal oldAmount = opp.Amount;
        opp.Amount = opp.Amount * (1 + increase);
        
        System.debug('    -> Amount increase: ' + oldAmount + ' -> ' + opp.Amount + ' (+' + (increase*100).intValue() + '%)');
        opportunityChanges.get(opp.Id).add('Amount: +' + (increase*100).intValue() + '%');
        return true;
    }
    
    /**
     * Decrease opportunity amount by 15-40%
     */
    private static Boolean decreaseAmount(Opportunity opp) {
        Decimal decrease = 0.15 + (Math.random() * 0.25); // 15-40%
        Decimal oldAmount = opp.Amount;
        opp.Amount = opp.Amount * (1 - decrease);
        
        System.debug('    -> Amount decrease: ' + oldAmount + ' -> ' + opp.Amount + ' (-' + (decrease*100).intValue() + '%)');
        opportunityChanges.get(opp.Id).add('Amount: -' + (decrease*100).intValue() + '%');
        return true;
    }
    
    /**
     * Extend POP by 3-12 months
     */
    private static Boolean extendPOP(Opportunity opp) {
        if (opp.Period_of_Performance__c == null) {
            opp.Period_of_Performance__c = 12; // Default
        }
        
        Integer extension = (Integer)(Math.random() * 10) + 3; // 3-12 months
        Decimal oldPOP = opp.Period_of_Performance__c;
        opp.Period_of_Performance__c = opp.Period_of_Performance__c + extension;
        
        System.debug('    -> POP extension: ' + oldPOP + ' -> ' + opp.Period_of_Performance__c + ' (+' + extension + ' months)');
        opportunityChanges.get(opp.Id).add('POP: +' + extension + ' months');
        return true;
    }
    
    /**
     * Reduce POP by 1-6 months (minimum 1 month)
     */
    private static Boolean reducePOP(Opportunity opp) {
        if (opp.Period_of_Performance__c == null || opp.Period_of_Performance__c <= 1) {
            return false; // Can't reduce further
        }
        
        Integer reduction = (Integer)(Math.random() * 6) + 1; // 1-6 months
        if (reduction >= opp.Period_of_Performance__c) {
            reduction = Integer.valueOf(opp.Period_of_Performance__c - 1); // Leave at least 1 month
        }
        
        Decimal oldPOP = opp.Period_of_Performance__c;
        opp.Period_of_Performance__c = opp.Period_of_Performance__c - reduction;
        
        System.debug('    -> POP reduction: ' + oldPOP + ' -> ' + opp.Period_of_Performance__c + ' (-' + reduction + ' months)');
        opportunityChanges.get(opp.Id).add('POP: -' + reduction + ' months');
        return true;
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
        else if (stage == 'Closed Won') return 100;
        else if (stage == 'Closed Lost') return 0;
        else return 50; // Default
    }
    
    // =============================================================================
    // EXISTING METHODS (UNCHANGED)
    // =============================================================================
    
    /**
     * STEP 1: Shift all snapshot data (preserve current amounts for now)
     */
    private static Map<String, Integer> shiftAllSnapshotData(String nextMonthString) {
        List<Opty_Sd__c> snapshots = [
            SELECT Id, Amount0__c, Amount1__c, Amount2__c, Amount3__c, Amount4__c, Amount5__c,
                   Reason0__c, Reason1__c, Reason2__c, Reason3__c, Reason4__c, Reason5__c,
                   Month0__c, Month1__c, Month2__c, Month3__c, Month4__c, Month5__c
            FROM Opty_Sd__c
        ];
        
        List<Opty_Sd__c> snapshotsToUpdate = new List<Opty_Sd__c>();
        
        for (Opty_Sd__c snapshot : snapshots) {
            // Shift all data one position, keeping Amount0__c for now
            shiftSnapshotDataOnly(snapshot, nextMonthString);
            snapshotsToUpdate.add(snapshot);
        }
        
        if (!snapshotsToUpdate.isEmpty()) {
            update snapshotsToUpdate;
        }
        
        Map<String, Integer> results = new Map<String, Integer>();
        results.put('recordsUpdated', snapshotsToUpdate.size());
        return results;
    }
    
    /**
     * STEP 3: Recalculate snapshot amounts after opportunity changes
     */
    private static Map<String, Integer> recalculateSnapshotAmounts(String nextMonthString) {
        List<Opty_Sd__c> snapshots = [
            SELECT Id, Amount0__c, Reason0__c,
                   Opportunity__c, Opportunity__r.Amount, Opportunity__r.StageName,
                   Opportunity__r.CloseDate, Opportunity__r.CreatedDate,
                   Opportunity__r.Period_of_Performance__c
            FROM Opty_Sd__c
            WHERE Opportunity__c != null
        ];
        
        List<Opty_Sd__c> snapshotsToUpdate = new List<Opty_Sd__c>();
        Date forecastMonth = ForecastUtilityService.parseDateString(nextMonthString);
        
        for (Opty_Sd__c snapshot : snapshots) {
            // Calculate POP-based monthly amount for this forecast month
            Decimal monthlyAmount = calculateMonthlyRevenueAmount(
                snapshot.Opportunity__r, 
                forecastMonth
            );
            
            // Apply stage-based probability and set new amounts/reasons
            if (snapshot.Opportunity__r.StageName == 'Closed Won') {
                snapshot.Amount0__c = monthlyAmount; // Monthly portion only
                snapshot.Reason0__c = 'Closed Won';
            } else if (snapshot.Opportunity__r.StageName == 'Closed Lost') {
                snapshot.Amount0__c = 0;
                snapshot.Reason0__c = 'Closed Lost';
            } else {
                // For open opportunities, use monthly amount * probability
                Decimal probability = getProbabilityByStage(snapshot.Opportunity__r.StageName) / 100.0;
                snapshot.Amount0__c = monthlyAmount * probability;
                snapshot.Reason0__c = 'Pipeline Update';
            }
            
            snapshotsToUpdate.add(snapshot);
        }
        
        if (!snapshotsToUpdate.isEmpty()) {
            update snapshotsToUpdate;
        }
        
        Map<String, Integer> results = new Map<String, Integer>();
        results.put('recordsUpdated', snapshotsToUpdate.size());
        return results;
    }
    
    /**
     * Shift snapshot data one position ONLY (don't recalculate amounts yet)
     */
    private static void shiftSnapshotDataOnly(Opty_Sd__c snapshot, String nextMonthString) {
        // Shift amounts (keep Amount0__c unchanged for now)
        snapshot.Amount5__c = snapshot.Amount4__c;
        snapshot.Amount4__c = snapshot.Amount3__c;
        snapshot.Amount3__c = snapshot.Amount2__c;
        snapshot.Amount2__c = snapshot.Amount1__c;
        snapshot.Amount1__c = snapshot.Amount0__c; // Store current as previous
        // Amount0__c stays the same until recalculation step
        
        // Shift reasons (clear current reason)
        snapshot.Reason5__c = snapshot.Reason4__c;
        snapshot.Reason4__c = snapshot.Reason3__c;
        snapshot.Reason3__c = snapshot.Reason2__c;
        snapshot.Reason2__c = snapshot.Reason1__c;
        snapshot.Reason1__c = snapshot.Reason0__c; // Store current reason as previous
        snapshot.Reason0__c = ''; // Clear current reason - will be set during recalculation
        
        // Shift months
        snapshot.Month5__c = snapshot.Month4__c;
        snapshot.Month4__c = snapshot.Month3__c;
        snapshot.Month3__c = snapshot.Month2__c;
        snapshot.Month2__c = snapshot.Month1__c;
        snapshot.Month1__c = snapshot.Month0__c;
        snapshot.Month0__c = nextMonthString; // Set new current month
    }
    
    /**
     * Calculate monthly revenue amount based on Period of Performance
     */
    private static Decimal calculateMonthlyRevenueAmount(Opportunity opp, Date forecastMonth) {
        if (opp.Amount == null || opp.Amount <= 0) {
            return 0;
        }
        
        // Get contract duration from Period_of_Performance__c field
        Integer contractMonths = opp.Period_of_Performance__c != null ? 
                                Integer.valueOf(opp.Period_of_Performance__c) : 12;
        
        if (contractMonths <= 0) {
            contractMonths = 12; // Default fallback
        }
        
        // Calculate monthly revenue (even distribution)
        Decimal monthlyRevenue = opp.Amount / contractMonths;
        
        // Determine contract start date (when contract actually begins)
        Date contractStartDate = opp.CloseDate; // Use close date as contract start
        
        // Calculate contract end date
        Date contractEndDate = contractStartDate.addMonths(contractMonths - 1);
        
        // Use the simpler integer comparison method
        Integer forecastYear = forecastMonth.year();
        Integer forecastMonthNum = forecastMonth.month();
        Integer startYear = contractStartDate.year();
        Integer startMonthNum = contractStartDate.month();
        Integer endYear = contractEndDate.year();
        Integer endMonthNum = contractEndDate.month();
        
        // Convert to integers for easy comparison (YYYY * 12 + MM)
        Integer forecastInt = forecastYear * 12 + forecastMonthNum;
        Integer startInt = startYear * 12 + startMonthNum;
        Integer endInt = endYear * 12 + endMonthNum;
        
        // Check if forecast month falls within contract period
        if (forecastInt >= startInt && forecastInt <= endInt) {
            return monthlyRevenue;
        } else {
            return 0; // Outside contract period
        }
    }
    
    /**
     * Synchronize all snapshots to current month
     */
    public static void synchronizeAllSnapshotsToCurrentMonth(String targetMonth) {
        try {
            List<Opty_Sd__c> allSnapshots = [
                SELECT Id, Month0__c 
                FROM Opty_Sd__c
            ];
            
            List<Opty_Sd__c> snapshotsToUpdate = new List<Opty_Sd__c>();
            
            for (Opty_Sd__c snapshot : allSnapshots) {
                if (snapshot.Month0__c != targetMonth) {
                    snapshot.Month0__c = targetMonth;
                    snapshotsToUpdate.add(snapshot);
                }
            }
            
            if (!snapshotsToUpdate.isEmpty()) {
                update snapshotsToUpdate;
                System.debug('Synchronized ' + snapshotsToUpdate.size() + ' snapshots to month: ' + targetMonth);
            } else {
                System.debug('All snapshots already synchronized to month: ' + targetMonth);
            }
            
        } catch (Exception e) {
            System.debug('Error synchronizing snapshots: ' + e.getMessage());
            throw new AuraHandledException('Error synchronizing snapshots: ' + e.getMessage());
        }
    }
}