// opportunityRecap.js - UPDATED WITH CREATED OPPORTUNITIES AND SD REASONS
import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getOpportunityRecap from '@salesforce/apex/OpportunityRecapController.getOpportunityRecap';
import getCurrentForecastMonth from '@salesforce/apex/ForecastManagerLWC.getCurrentForecastMonth';

export default class OpportunityRecap extends LightningElement {
    @track currentDate = new Date(2025, 1, 1); // Default fallback
    @track forecastMonthStr = '';
    wonOpportunities = [];
    lostOpportunities = [];
    shiftedOpportunities = [];
    createdOpportunities = []; // NEW
    wonCount = 0;
    lostCount = 0;
    shiftedCount = 0;
    createdCount = 0; // NEW
    wonAmount = 0;
    lostAmount = 0;
    shiftedAmount = 0;
    createdAmount = 0; // NEW
    isLoading = true;
    error;
    
    // Track wired result for refreshApex
    wiredOpportunityResult;

    // Load forecast month imperatively to avoid caching issues
    connectedCallback() {
        this.loadCurrentForecastMonth();
        // Set up periodic refresh to detect month changes
        this.refreshInterval = setInterval(() => {
            this.loadCurrentForecastMonth();
        }, 50000000); // Check every 500 seconds
    }

    disconnectedCallback() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }

    async loadCurrentForecastMonth() {
        try {
            const data = await getCurrentForecastMonth();
            if (data && data !== this.forecastMonthStr) {
                this.forecastMonthStr = data;
                this.updateCurrentDate(data);
                console.log('Opportunity Recap: Forecast month updated to', data);
            }
        } catch (error) {
            console.error('Opportunity Recap: Error loading forecast month:', error);
        }
    }

    @wire(getOpportunityRecap, { 
        year: '$currentYear', 
        month: '$currentMonth' 
    })
    wiredOpportunityRecap(result) {
        this.wiredOpportunityResult = result;
        this.isLoading = false;
        
        if (result.data) {
            this.processOpportunityData(result.data);
        } else if (result.error) {
            this.error = result.error;
            this.wonOpportunities = [];
            this.lostOpportunities = [];
            this.shiftedOpportunities = [];
            this.createdOpportunities = []; // NEW
        }
    }

    // **NEW**: Method to update current date from forecast month string
    updateCurrentDate(forecastMonthStr) {
        try {
            // Parse forecast month string (format: "M/d/yyyy" like "2/1/2025")
            const dateParts = forecastMonthStr.split('/');
            if (dateParts.length === 3) {
                const month = parseInt(dateParts[0]) - 1; // JavaScript months are 0-indexed
                const day = parseInt(dateParts[1]);
                const year = parseInt(dateParts[2]);
                
                const newDate = new Date(year, month, day);
                
                // Only update if the month/year actually changed
                if (newDate.getMonth() !== this.currentDate.getMonth() || 
                    newDate.getFullYear() !== this.currentDate.getFullYear()) {
                    
                    this.currentDate = newDate;
                    console.log('Updated current date to:', this.currentDate);
                    
                    // Force refresh of opportunity data for new month
                    this.refreshOpportunityData();
                }
            } else {
                console.warn('Could not parse forecast month string:', forecastMonthStr);
            }
        } catch (error) {
            console.error('Error parsing forecast month:', error);
        }
    }

    // **NEW**: Force refresh opportunity data using refreshApex
    async refreshOpportunityData() {
        try {
            this.isLoading = true;
            const prevDate = this.getPreviousMonth();
            console.log('Refreshing opportunity data for PREVIOUS month:', this.currentYear, '/', this.currentMonth, 
                       '(Current forecast month:', this.currentDate.getMonth() + 1, '/', this.currentDate.getFullYear(), ')');
            
            // Use refreshApex to force refresh the wired data
            await refreshApex(this.wiredOpportunityResult);
            
        } catch (error) {
            console.error('Error refreshing opportunity data:', error);
            this.error = error;
        } finally {
            this.isLoading = false;
        }
    }

    // **UPDATED**: Extract data processing into reusable method with created opportunities and SD reasons
    processOpportunityData(data) {
        this.wonOpportunities = (data.wonOpportunities || []).map(opp => ({
            ...opp,
            AccountName: opp.Account ? opp.Account.Name : '',
            OwnerName: opp.Owner ? opp.Owner.Name : '',
            FormattedCloseDate: this.formatDate(opp.CloseDate),
            OpportunityUrl: `/lightning/r/Opportunity/${opp.Id}/view`,
            AccountUrl: opp.Account ? `/lightning/r/Account/${opp.Account.Id}/view` : ''
        }));
        
        // UPDATED: Lost opportunities with reason from SD records instead of owner
        this.lostOpportunities = (data.lostOpportunities || []).map(opp => {
            // Get reason from the separate map created in Apex
            let sdReason = '';
            if (data.oppIdToReasonMap && data.oppIdToReasonMap[opp.Id]) {
                sdReason = data.oppIdToReasonMap[opp.Id];
            }
            
            return {
                ...opp,
                AccountName: opp.Account ? opp.Account.Name : '',
                OwnerName: opp.Owner ? opp.Owner.Name : '',
                LossReason: sdReason || opp.Reason_for_Change__c || 'Not specified',
                OpportunityUrl: `/lightning/r/Opportunity/${opp.Id}/view`,
                AccountUrl: opp.Account ? `/lightning/r/Account/${opp.Account.Id}/view` : ''
            };
        });

        this.shiftedOpportunities = (data.shiftedOpportunities || []).map(opp => {
            // Get reason from the separate map created in Apex
            let sdReason = '';
            if (data.oppIdToReasonMap && data.oppIdToReasonMap[opp.Id]) {
                sdReason = data.oppIdToReasonMap[opp.Id];
            }
            
            let newCloseDate = new Date(opp.CloseDate);
            newCloseDate.setDate(newCloseDate.getDate() + 30);
            
            return {
                ...opp,
                AccountName: opp.Account ? opp.Account.Name : '',
                OwnerName: opp.Owner ? opp.Owner.Name : '',
                FormattedNewCloseDate: this.formatDate(newCloseDate.toISOString().split('T')[0]),
                ShiftReason: sdReason || opp.Reason_for_Change__c || 'Not specified',
                OpportunityUrl: `/lightning/r/Opportunity/${opp.Id}/view`,
                AccountUrl: opp.Account ? `/lightning/r/Account/${opp.Account.Id}/view` : ''
            };
        });
        
        // NEW: Created opportunities processing
        this.createdOpportunities = (data.createdOpportunities || []).map(opp => ({
            ...opp,
            AccountName: opp.Account ? opp.Account.Name : '',
            OwnerName: opp.Owner ? opp.Owner.Name : '',
            FormattedCloseDate: this.formatDate(opp.CloseDate),
            FormattedCreatedDate: this.formatDate(opp.CreatedDate),
            OpportunityUrl: `/lightning/r/Opportunity/${opp.Id}/view`,
            AccountUrl: opp.Account ? `/lightning/r/Account/${opp.Account.Id}/view` : ''
        }));
        
        this.wonCount = this.wonOpportunities.length;
        this.lostCount = this.lostOpportunities.length;
        this.shiftedCount = this.shiftedOpportunities.length;
        this.createdCount = this.createdOpportunities.length; // NEW
        
        this.wonAmount = this.wonOpportunities.reduce((total, opp) => total + (opp.Amount || 0), 0);
        this.lostAmount = this.lostOpportunities.reduce((total, opp) => total + (opp.Amount || 0), 0);
        this.shiftedAmount = this.shiftedOpportunities.reduce((total, opp) => total + (opp.Amount || 0), 0);
        this.createdAmount = this.createdOpportunities.reduce((total, opp) => total + (opp.Amount || 0), 0); // NEW
        
        this.error = undefined;
    }

    get currentYear() {
        // Get PREVIOUS month's year for the recap
        const prevDate = this.getPreviousMonth();
        return prevDate.getFullYear();
    }

    get currentMonth() {
        // Get PREVIOUS month's month for the recap
        const prevDate = this.getPreviousMonth();
        return prevDate.getMonth() + 1;
    }

    get currentMonthName() {
        // Show PREVIOUS month name in the title
        const monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'];
        const prevDate = this.getPreviousMonth();
        return monthNames[prevDate.getMonth()];
    }

    // **NEW**: Calculate previous month from current forecast month
    getPreviousMonth() {
        const currentMonth = this.currentDate.getMonth();
        const currentYear = this.currentDate.getFullYear();
        
        if (currentMonth === 0) {
            // January -> go to December of previous year
            return new Date(currentYear - 1, 11, 1);
        } else {
            // Go to previous month of same year
            return new Date(currentYear, currentMonth - 1, 1);
        }
    }

    get cardTitle() {
        return `${this.currentMonthName} ${this.currentYear} Opportunity Recap (Previous Month)`;
    }

    get debugDateString() {
        const prevDate = this.getPreviousMonth();
        return `Current Forecast: ${this.currentDate.toString()} | Showing Recap For: ${prevDate.toString()} | Forecast Month: ${this.forecastMonthStr}`;
    }

    get noDataMessage() {
        return `No opportunities were closed in ${this.currentMonthName} ${this.currentYear} (previous month).`;
    }

    get formattedWonAmount() {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(this.wonAmount);
    }

    get formattedLostAmount() {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(this.lostAmount);
    }

    get formattedShiftedAmount() {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(this.shiftedAmount);
    }

    // NEW: Formatted created amount
    get formattedCreatedAmount() {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(this.createdAmount);
    }

    get hasWonOpportunities() {
        return this.wonOpportunities && this.wonOpportunities.length > 0;
    }

    get hasLostOpportunities() {
        return this.lostOpportunities && this.lostOpportunities.length > 0;
    }

    get hasShiftedOpportunities() {
        return this.shiftedOpportunities && this.shiftedOpportunities.length > 0;
    }

    // NEW: Has created opportunities getter
    get hasCreatedOpportunities() {
        return this.createdOpportunities && this.createdOpportunities.length > 0;
    }

    get wonColumns() {
        return [
            { label: 'Opportunity Name', fieldName: 'Name', type: 'text' },
            { label: 'Account', fieldName: 'AccountName', type: 'text' },
            { label: 'Amount', fieldName: 'Amount', type: 'currency' },
            { 
                label: 'Close Date', fieldName: 'CloseDate', type: 'date-local', typeAttributes: {
                    month: '2-digit', day: '2-digit', year: 'numeric'
                }
            },
            { label: 'Owner', fieldName: 'OwnerName', type: 'text' }
        ];
    }

    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        return date.toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        });
    }

    // UPDATED: Lost columns with reason instead of owner
    get lostColumns() {
        return [
            { label: 'Opportunity Name', fieldName: 'Name', type: 'text' },
            { label: 'Account', fieldName: 'AccountName', type: 'text' },
            { label: 'Amount', fieldName: 'Amount', type: 'currency' },
            { 
                label: 'Close Date', 
                fieldName: 'CloseDate', 
                type: 'date-local',
                typeAttributes: {
                    month: '2-digit',
                    day: '2-digit',
                    year: 'numeric'
                }
            },
            { label: 'Reason', fieldName: 'LossReason', type: 'text' } // CHANGED from Owner to Reason
        ];
    }

    get shiftedColumns() {
        return [
            { label: 'Opportunity Name', fieldName: 'Name', type: 'text' },
            { label: 'Account', fieldName: 'AccountName', type: 'text' },
            { label: 'Amount', fieldName: 'Amount', type: 'currency' },
            { label: 'Original Close Date', fieldName: 'CloseDate', type: 'date-local',
                typeAttributes: {
                    month: '2-digit',
                    day: '2-digit',
                    year: 'numeric'
                }
            },
            { label: 'Reason', fieldName: 'ShiftReason', type: 'text' } // CHANGED from Owner to Reason
        ];
    }

    // NEW: Created opportunities columns
    get createdColumns() {
        return [
            { label: 'Opportunity Name', fieldName: 'Name', type: 'text' },
            { label: 'Account', fieldName: 'AccountName', type: 'text' },
            { label: 'Amount', fieldName: 'Amount', type: 'currency' },
            { 
                label: 'Close Date', 
                fieldName: 'CloseDate', 
                type: 'date-local',
                typeAttributes: {
                    month: '2-digit',
                    day: '2-digit',
                    year: 'numeric'
                }
            }
        ];
    }
}