public with sharing class ForecastMonthService {

   private static String CURRENT_FORECAST_MONTH_OVERRIDE = null;

   public static void setCurrentForecastMonth(String monthValue) {
       CURRENT_FORECAST_MONTH_OVERRIDE = monthValue;
   }

   public static String getCurrentForecastMonthOverride() {
       return CURRENT_FORECAST_MONTH_OVERRIDE;
   }
   
   /**
    * Advance forecast to next month with simplified, consistent date handling
    */
   public static Map<String, String> advanceToNextMonth() {
       try {
           ForecastUtilityService.validateAdminAccess();
           
           // 1. Get current forecast month (same for ALL records)
           String currentMonthStr = ForecastUtilityService.getCurrentForecastMonth();
           
           // 2. Calculate the SINGLE next month value for ALL records
           Date currentForecastMonth = ForecastUtilityService.parseDateString(currentMonthStr);
           Date nextMonth = currentForecastMonth.addMonths(1);
           String nextMonthString = ForecastUtilityService.formatDateString(nextMonth);
           
           // Set the global override
           setCurrentForecastMonth(nextMonthString);
            
            // 3. STEP 1: Shift all snapshot data first
            Map<String, Integer> shiftResults = shiftAllSnapshotData(currentMonthStr, nextMonthString);
            
            // 4. STEP 2: Apply opportunity changes
Boolean isBadMonth = Math.random() < 0.0; // TEMP 0% chance of bad month
            String monthType = isBadMonth ? 'Bad' : 'Good';
            Map<String, Integer> opportunityResults = simulationExecution(currentForecastMonth, nextMonth, isBadMonth);
//Map<String, Integer> opportunityResults = processOpportunityChangesStructured(currentForecastMonth, nextMonth, isBadMonth);
            
            // 5. STEP 3: Recalculate snapshot amounts based on changed opportunities
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
     * SIMPLIFIED: Shift all snapshot data using consistent next month value
     */
    private static Map<String, Integer> shiftAllSnapshotData(String currentMonthStr, String nextMonthString) {
        // Get ALL Opty_sd__c records that need updating
        List<Opty_sd__c> sdRecords = [
            SELECT Id, Month0__c, Month1__c, Month2__c, Month3__c, Month4__c, Month5__c,
                Amount0__c, Amount1__c, Amount2__c, Amount3__c, Amount4__c, Amount5__c,
                Reason0__c, Reason1__c, Reason2__c, Reason3__c, Reason4__c, Reason5__c,
                CloseDate0__c, CloseDate1__c, CloseDate2__c, CloseDate3__c, CloseDate4__c, CloseDate5__c, Opportunity__r.CloseDate

            FROM Opty_sd__c 
            WHERE Month0__c = :currentMonthStr
        ];
                
        // Shift ALL records using the SAME next month value
        for (Opty_sd__c sd : sdRecords) {
            // Shift months: 0→1, 1→2, 2→3, 3→4, 4→5, and set new 0
            sd.Month5__c = sd.Month4__c;
            sd.Month4__c = sd.Month3__c;
            sd.Month3__c = sd.Month2__c;
            sd.Month2__c = sd.Month1__c;
            sd.Month1__c = sd.Month0__c;  // Current month moves to position 1
            sd.Month0__c = CURRENT_FORECAST_MONTH_OVERRIDE;         
            // Shift amounts: 0→1, 1→2, 2→3, 3→4, 4→5, and keep current 0 for now
            sd.Amount5__c = sd.Amount4__c;
            sd.Amount4__c = sd.Amount3__c;
            sd.Amount3__c = sd.Amount2__c;
            sd.Amount2__c = sd.Amount1__c;
            sd.Amount1__c = sd.Amount0__c;
            // Keep Amount0__c unchanged for now - will be recalculated later
            
            // Shift reasons: 0→1, 1→2, 2→3, 3→4, 4→5, and clear current 0
            sd.Reason5__c = sd.Reason4__c;
            sd.Reason4__c = sd.Reason3__c;
            sd.Reason3__c = sd.Reason2__c;
            sd.Reason2__c = sd.Reason1__c;
            sd.Reason1__c = sd.Reason0__c;
            sd.Reason0__c = '';  // Clear for recalculation

            // Shift CloseDate: 0→1, 1→2, 2→3, 3→4, 4→5, and set new 0
            sd.CloseDate5__c = sd.CloseDate4__c;
            sd.CloseDate4__c = sd.CloseDate3__c;
            sd.CloseDate3__c = sd.CloseDate2__c;
            sd.CloseDate2__c = sd.CloseDate1__c;
            sd.CloseDate1__c = sd.CloseDate0__c;  // Current close date moves to position 1
            sd.CloseDate0__c = sd.Opportunity__r.CloseDate;     // Set new current close date
// clear the reason at the opportunity level for upcoming month change reasons - TO DEVELOP
        }
        
        // Update ALL records in one DML operation
        if (!sdRecords.isEmpty()) {
            update sdRecords;
        }
        
        Map<String, Integer> results = new Map<String, Integer>();
        results.put('recordsUpdated', sdRecords.size());
        return results;
    }
//*CONSTRUCTION***********************
//** EXCLUDE ANY SAVED CLOSED WON/LOST OPPORTUNITIES**
        private static Map<String, Integer> simulationExecution(Date currentForecastMonth, Date nextMonth, Boolean isBadMonth)
    {

            List<Opportunity> opportunities = [
            SELECT Id, Name, StageName, Amount, CloseDate, Probability, 
                   CreatedDate, LeadSource, Period_of_Performance__c, Reason_for_Change__c
            FROM Opportunity 
            WHERE (StageName NOT IN ('Closed Won', 'Closed Lost'))
            OR (CloseDate < TODAY AND StageName NOT IN ('Closed Won', 'Closed Lost'))
            ORDER BY CloseDate, CreatedDate
        ];
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        List<Opportunity> opportunitiesToCreate = new List<Opportunity>(); // ADD THIS LINE
        Integer totalProcessed = 0;
        Integer totalChanged = 0;
        Integer wonCount = 0;
        Integer lostCount = 0;
        Integer createdCount = 0;
        
        for (Opportunity opp : opportunities) {
            totalProcessed++;
            Boolean wasChanged = false;
            String reasonTracker ='';
            if (opp.StageName != 'Closed Won' && opp.StageName != 'Closed Lost'){    
            Double randomValue = Math.random();        
  
        //1. ALL SOME MONTH SHIFT   opp, nextMonth -- future development isBadMonth
   //     if (isBadMonth) {
            if (randomValue >= .5) {
                Integer pushMonths = (Integer)(Math.random() * 6) + 1;
                opp.CloseDate = opp.CloseDate.addMonths(pushMonths);
                reasonTracker += '+' + pushMonths + ' month(s), ';
                wasChanged = true;
                } else if (randomValue < 0.5) {
    Integer pushMonths = (Integer)(Math.random() * 3) + 1;
    Date oldCloseDate = opp.CloseDate;
    Date currentMonth = currentForecastMonth.toStartOfMonth();
    Date newCloseDate = oldCloseDate.addMonths(-pushMonths);
    
    if (newCloseDate < currentMonth) {
        // Calculate actual months from old date to current month
        pushMonths = Math.abs(oldCloseDate.monthsBetween(currentMonth));
        opp.CloseDate = currentMonth;
    } else {
        // Normal backward shift is valid
        opp.CloseDate = newCloseDate;
    }
    
    reasonTracker += '-' + pushMonths + ' month(s), ';
    wasChanged = true;
    } else {}
            //}
  
//2. ALL SOME AMOUNT CHANGE opp
            randomValue = Math.random();
            if (randomValue >= 0.5){
            Decimal increase = 0.20 + (Math.random() * 0.55);
            opp.Amount = opp.Amount * (1 + increase);
            reasonTracker += 'revenue +' + (increase * 100).setScale(0) + '% ($' + opp.Amount.setScale(0).format() + '), ';
            wasChanged = true;
            } else if (randomValue < 0.5){
            Decimal decrease = 0.15 + (Math.random() * 0.25);
            opp.Amount = opp.Amount * (1 - decrease);
            reasonTracker += 'revenue -' + (decrease * 100).setScale(0) + '% ($' + opp.Amount.setScale(0).format() + '), ';            wasChanged = true;
            } else {}

//3. ALL SOME POP CHANGE    opp - need to add total revenue change logic in output text
        randomValue = Math.random();

        if (opp.Period_of_Performance__c == null) {
            opp.Period_of_Performance__c = 12;
        }
        if (randomValue >= 0.5){
            Integer extension = (Integer)(Math.random() * 10) + 3;
            opp.Period_of_Performance__c = opp.Period_of_Performance__c + extension;
            wasChanged = true;
            reasonTracker += 'PoP +' + extension + ', ';    
        } else if (randomValue < 0.5){
            if (opp.Period_of_Performance__c > 1) {
                Integer reduction = (Integer)(Math.random() * 6) + 1;
                // Ensure POP doesn't go below 1
                if (reduction >= opp.Period_of_Performance__c) {
                    reduction = Integer.valueOf(opp.Period_of_Performance__c - 1);
                }
                opp.Period_of_Performance__c = opp.Period_of_Performance__c - reduction;
                wasChanged = true;
                reasonTracker += 'PoP -' + reduction + ', ';    
        }
//4. ALL SOME STAGE CHANGE ~(CLOSED WON OR CLOSED LOST) opp


//4. ALL SOME STAGE CHANGE
randomValue = Math.random();

// Define stages as a list for easier manipulation
List<String> stages = new List<String>{
    'Prospecting',           // 0
    'Qualification',         // 1
    'Needs Analysis',        // 2
    'Value Proposition',     // 3
    'Id. Decision Makers',   // 4
    'Proposal/Price Quote',  // 5
    'Negotiation/Review'     // 6
};

// Find current stage index
Integer currentStageIndex = -1;
for (Integer i = 0; i < stages.size(); i++) {
    if (stages[i] == opp.StageName) {
        currentStageIndex = i;
        break;
    }
}

// Only process if we found the stage and it's not closed
if (currentStageIndex != -1) {
    if (randomValue >= 0.5) {
        // Forward progression
        if (currentStageIndex < 6) { // Can't go beyond Negotiation/Review
            Integer maxJump = 6 - currentStageIndex;
            Integer jumpStages = (Integer)(Math.random() * maxJump) + 1;
            Integer newStageIndex = currentStageIndex + jumpStages;
            
            opp.StageName = stages[newStageIndex];
            opp.Probability = getProbabilityByStage(opp.StageName);
            wasChanged = true;
            reasonTracker += 'Stage ↑' + jumpStages + ' to ' + opp.StageName + ', ';
        }
    } else {
        // Backward progression
        if (currentStageIndex > 0) { // Can't go below Prospecting
            Integer maxJump = currentStageIndex;
            Integer jumpStages = (Integer)(Math.random() * maxJump) + 1;
            Integer newStageIndex = currentStageIndex - jumpStages;
            
            opp.StageName = stages[newStageIndex];
            opp.Probability = getProbabilityByStage(opp.StageName);
            wasChanged = true;
            reasonTracker += 'Stage ↓' + jumpStages + ' to ' + opp.StageName + ', ';
        }
    }
}

//5. ALL SOME CLOSED LOST || CURRENT WON || CURRENT SHIFT  opp - need to consider future month opportunities that are closedate change to current month then won
        randomValue = Math.random();
        if (randomValue >.25 && randomValue <.4){
        opp.StageName = 'Closed Lost';
        opp.Probability = 0;
        reasonTracker += ' Closed Lost';
        wasChanged = true;
        } else if (randomValue >=.4 && opp.CloseDate.year() == currentForecastMonth.year() && 
        opp.CloseDate.month() == currentForecastMonth.month()){
        opp.StageName = 'Closed Won';
        opp.Probability = 100;
        reasonTracker += ' Closed Won';
        wasChanged = true;
        } else if (randomValue <.25 && opp.CloseDate.year() == currentForecastMonth.year() && 
        opp.CloseDate.month() == currentForecastMonth.month()){
        opp.CloseDate = opp.CloseDate.addMonths(1);
        reasonTracker += ' +1 month (no activity)';
        wasChanged = true;
        }
    }}

        if (wasChanged) {
            opp.Reason_for_Change__c = reasonTracker;
            opportunitiesToUpdate.add(opp);
            totalChanged++;
        }

    }
                    // Update opportunities
        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }

//6. CREATE NEW OPPORTUNITIES (0-5 random)
Double randomValue = Math.random();

if (randomValue < 1) {  // 100% chance to create new opportunities
    Integer numToCreate = (Integer)(Math.random() * 6); // 0 to 5
    
    for (Integer i = 0; i < numToCreate; i++) {
        Opportunity newOpp = new Opportunity();
        
        // Basic fields - add index to make names unique
        newOpp.Name = 'Auto-Generated Opp ' + DateTime.now().format('MMddHHmmss') + '-' + i;
        newOpp.CloseDate = currentForecastMonth.addMonths((Integer)(Math.random() * 12) + 1); // 1-12 months out
        newOpp.Amount = 50000 + (Math.random() * 450000); // $50k to $500k
        
        // Random stage
        List<String> createStages = new List<String>{
            'Prospecting', 'Qualification', 'Needs Analysis', 
            'Value Proposition', 'Id. Decision Makers', 
            'Proposal/Price Quote', 'Negotiation/Review'
        };
        Integer stageIndex = (Integer)(Math.random() * createStages.size());
        newOpp.StageName = createStages[stageIndex];
        newOpp.Probability = getProbabilityByStage(newOpp.StageName);
        
        // Random POP
        newOpp.Period_of_Performance__c = (Integer)(Math.random() * 24) + 12; // 12-36 months
        
        // Lead source
        List<String> leadSources = new List<String>{'Web', 'Phone Inquiry', 'Partner Referral', 'Trade Show'};
        newOpp.LeadSource = leadSources[(Integer)(Math.random() * leadSources.size())];
        
        // Track creation
        newOpp.Reason_for_Change__c = 'New opportunity created';
        
        opportunitiesToCreate.add(newOpp);
        createdCount++;
    }
}
        // Insert new opportunities
if (!opportunitiesToCreate.isEmpty()) {
    insert opportunitiesToCreate;
}        
        Map<String, Integer> results = new Map<String, Integer>();
        results.put('totalProcessed', totalProcessed);
        results.put('totalChanged', totalChanged);
        results.put('wonCount', wonCount);
        results.put('lostCount', lostCount);
        results.put('createdCount', createdCount);      
        return results;

    }
            
    
    /**
     * Recalculate snapshot amounts after opportunity changes
     */
    private static Map<String, Integer> recalculateSnapshotAmounts(String nextMonthString) {
        List<Opty_sd__c> snapshots = [
            SELECT Id, Amount0__c, Reason0__c, CloseDate0__c,
                   Opportunity__c, Opportunity__r.Amount, Opportunity__r.StageName,
                   Opportunity__r.CloseDate, Opportunity__r.CreatedDate,
                   Opportunity__r.Period_of_Performance__c, Opportunity__r.Reason_for_Change__c
            FROM Opty_sd__c
            WHERE Opportunity__c != null AND Month0__c = :nextMonthString
        ];
        
        List<Opty_sd__c> snapshotsToUpdate = new List<Opty_sd__c>();
        Date forecastMonth = ForecastUtilityService.parseDateString(nextMonthString);
        
        for (Opty_sd__c snapshot : snapshots) {
            // Calculate POP-based monthly amount for this forecast month
            Decimal monthlyAmount = calculateMonthlyRevenueAmount(
                snapshot.Opportunity__r, 
                forecastMonth
            );
            
            // Apply stage-based probability and set new amounts/reasons
            if (snapshot.Opportunity__r.StageName == 'Closed Won') {
                snapshot.Amount0__c = monthlyAmount;
                snapshot.Reason0__c = 'Closed Won';
                snapshot.CloseDate0__c = snapshot.Opportunity__r.CloseDate;
            } else if (snapshot.Opportunity__r.StageName == 'Closed Lost') {
                snapshot.Amount0__c = 0;
                snapshot.Reason0__c = 'Closed Lost';
                snapshot.CloseDate0__c = snapshot.Opportunity__r.CloseDate;
            } else {
                // For open opportunities, use monthly amount * probability
                Decimal probability = getProbabilityByStage(snapshot.Opportunity__r.StageName) / 100.0;
                snapshot.Amount0__c = monthlyAmount * probability;
                snapshot.Reason0__c = snapshot.Opportunity__r.Reason_for_Change__c;
                snapshot.CloseDate0__c = snapshot.Opportunity__r.CloseDate;
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
        else return 50;
    }
    
    /**
     * Calculate monthly revenue amount based on Period of Performance
     */
    private static Decimal calculateMonthlyRevenueAmount(Opportunity opp, Date forecastMonth) {
        if (opp.Amount == null || opp.Amount <= 0) {
            return 0;
        }
        
        Integer contractMonths = opp.Period_of_Performance__c != null ? 
                                Integer.valueOf(opp.Period_of_Performance__c) : 12;
        
        if (contractMonths <= 0) {
            contractMonths = 12;
        }
        
        Decimal monthlyRevenue = opp.Amount / contractMonths;
        Date contractStartDate = opp.CloseDate;
        Date contractEndDate = contractStartDate.addMonths(contractMonths - 1);
        
        Integer forecastInt = forecastMonth.year() * 12 + forecastMonth.month();
        Integer startInt = contractStartDate.year() * 12 + contractStartDate.month();
        Integer endInt = contractEndDate.year() * 12 + contractEndDate.month();
        
        if (forecastInt >= startInt && forecastInt <= endInt) {
            return monthlyRevenue;
        } else {
            return 0;
        }
    }
    
    /**
     * Synchronize all snapshots to current month
     */
    public static void synchronizeAllSnapshotsToCurrentMonth(String targetMonth) {
        try {
            List<Opty_sd__c> allSnapshots = [
                SELECT Id, Month0__c 
                FROM Opty_sd__c
            ];
            
            List<Opty_sd__c> snapshotsToUpdate = new List<Opty_sd__c>();
            
            for (Opty_sd__c snapshot : allSnapshots) {
                if (snapshot.Month0__c != targetMonth) {
                    snapshot.Month0__c = targetMonth;
                    snapshotsToUpdate.add(snapshot);
                }
            }
            
            if (!snapshotsToUpdate.isEmpty()) {
                update snapshotsToUpdate;
            } else {
            }
            
        } catch (Exception e) {
            System.debug('Error synchronizing snapshots: ' + e.getMessage());
            throw new AuraHandledException('Error synchronizing snapshots: ' + e.getMessage());
        }
    }
}