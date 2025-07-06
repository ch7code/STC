// pipelineReconciliation.js
import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPipelineReconciliation from '@salesforce/apex/PipelineReconciliationController.getPipelineReconciliation';
import getCurrentForecastMonth from '@salesforce/apex/ForecastManagerLWC.getCurrentForecastMonth';

export default class PipelineReconciliation extends LightningElement {
    @track currentDate = new Date(2025, 1, 1); // Default fallback
    @track forecastMonthStr = '';
    @track reconciliationData = {};
    
    isLoading = true;
    error;
    
    // Track wired result for refreshApex
    wiredReconciliationResult;

    // Load forecast month imperatively to avoid caching issues
    connectedCallback() {
        this.loadCurrentForecastMonth();
    }

    async loadCurrentForecastMonth() {
        try {
            const data = await getCurrentForecastMonth();
            if (data && data !== this.forecastMonthStr) {
                this.forecastMonthStr = data;
                this.updateCurrentDate(data);
                console.log('Pipeline Reconciliation: Forecast month updated to', data);
            }
        } catch (error) {
            console.error('Pipeline Reconciliation: Error loading forecast month:', error);
        }
    }

    @wire(getPipelineReconciliation, { 
        year: '$currentYear', 
        month: '$currentMonth' 
    })
    wiredPipelineReconciliation(result) {
        this.wiredReconciliationResult = result;
        this.isLoading = false;
        
        if (result.data) {
            this.reconciliationData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.reconciliationData = {};
        }
    }

    // Update current date from forecast month string
    updateCurrentDate(forecastMonthStr) {
        try {
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
                    
                    // Force refresh of reconciliation data for new month
                    this.refreshReconciliationData();
                }
            } else {
                console.warn('Could not parse forecast month string:', forecastMonthStr);
            }
        } catch (error) {
            console.error('Error parsing forecast month:', error);
        }
    }

    // Force refresh reconciliation data using refreshApex
    async refreshReconciliationData() {
        try {
            this.isLoading = true;
            await refreshApex(this.wiredReconciliationResult);
        } catch (error) {
            console.error('Error refreshing reconciliation data:', error);
            this.error = error;
        } finally {
            this.isLoading = false;
        }
    }

    // Get previous month for analysis
    getPreviousMonth() {
        const currentMonth = this.currentDate.getMonth();
        const currentYear = this.currentDate.getFullYear();
        
        if (currentMonth === 0) {
            return new Date(currentYear - 1, 11, 1);
        } else {
            return new Date(currentYear, currentMonth - 1, 1);
        }
    }

    get currentYear() {
        const prevDate = this.getPreviousMonth();
        return prevDate.getFullYear();
    }

    get currentMonth() {
        const prevDate = this.getPreviousMonth();
        return prevDate.getMonth() + 1;
    }

    get currentMonthName() {
        const monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'];
        const prevDate = this.getPreviousMonth();
        return monthNames[prevDate.getMonth()];
    }

    get cardTitle() {
        return `${this.currentMonthName} ${this.currentYear} Pipeline Reconciliation`;
    }

    // Summary formatting
    get formattedPreviousTotal() {
        return this.formatCurrency(this.reconciliationData.previousPipelineTotal || 0);
    }

    get formattedCurrentTotal() {
        return this.formatCurrency(this.reconciliationData.currentPipelineTotal || 0);
    }

    get formattedNetChange() {
        const netChange = this.reconciliationData.netPipelineChange || 0;
        return this.formatCurrencyWithSign(netChange);
    }

    get netChangeClass() {
        const netChange = this.reconciliationData.netPipelineChange || 0;
        return netChange >= 0 ? 'summary-value positive' : 'summary-value negative';
    }

    get formattedReconciliation() {
        return this.formatCurrencyWithSign(this.reconciliationData.reconciliationTotal || 0);
    }

    get reconciliationClass() {
        const reconciliation = this.reconciliationData.reconciliationTotal || 0;
        return reconciliation >= 0 ? 'summary-value positive' : 'summary-value negative';
    }

    get reconciliationIcon() {
        const netChange = this.reconciliationData.netPipelineChange || 0;
        const reconciliation = this.reconciliationData.reconciliationTotal || 0;
        const difference = Math.abs(netChange - reconciliation);
        
        return difference < 1000 ? 'utility:success' : 'utility:warning';
    }

    get reconciliationVariant() {
        const netChange = this.reconciliationData.netPipelineChange || 0;
        const reconciliation = this.reconciliationData.reconciliationTotal || 0;
        const difference = Math.abs(netChange - reconciliation);
        
        return difference < 1000 ? 'success' : 'warning';
    }

    get reconciliationStatus() {
        const netChange = this.reconciliationData.netPipelineChange || 0;
        const reconciliation = this.reconciliationData.reconciliationTotal || 0;
        const difference = Math.abs(netChange - reconciliation);
        
        return difference < 1000 ? 'Balanced' : 'Check Required';
    }

    // Category data and formatting
    get wonOpportunities() {
        return this.processOpportunityData(this.reconciliationData.wonOpportunities || []);
    }

    get lostOpportunities() {
        return this.processOpportunityData(this.reconciliationData.lostOpportunities || []);
    }

    get createdOpportunities() {
        return this.processOpportunityData(this.reconciliationData.createdOpportunities || []);
    }

    get shiftedOpportunities() {
        return this.processOpportunityData(this.reconciliationData.shiftedOpportunities || []);
    }

    get changedOpportunities() {
        return this.processOpportunityData(this.reconciliationData.changedOpportunities || []);
    }

    // Process opportunity data for display
    processOpportunityData(opportunities) {
        return opportunities.map(oppChange => ({
            ...oppChange,
            'opportunity.Id': oppChange.opportunity.Id,
            'opportunity.Name': oppChange.opportunity.Name,
            'opportunity.AccountName': oppChange.opportunity.Account ? oppChange.opportunity.Account.Name : '',
            'opportunity.Amount': oppChange.opportunity.Amount,
            'opportunity.StageName': oppChange.opportunity.StageName,
            'opportunity.CloseDate': oppChange.opportunity.CloseDate,
            'formattedAmount': this.formatCurrency(oppChange.opportunity.Amount || 0),
            'formattedDelta': this.formatCurrencyWithSign(oppChange.amountDelta || 0),
            'metadata': oppChange.metadata || ''
        }));
    }

    // Counts and totals
    get wonCount() {
        return (this.reconciliationData.wonOpportunities || []).length;
    }

    get lostCount() {
        return (this.reconciliationData.lostOpportunities || []).length;
    }

    get createdCount() {
        return (this.reconciliationData.createdOpportunities || []).length;
    }

    get shiftedCount() {
        return (this.reconciliationData.shiftedOpportunities || []).length;
    }

    get changedCount() {
        return (this.reconciliationData.changedOpportunities || []).length;
    }

    get formattedWonTotal() {
        return this.formatCurrency(this.reconciliationData.wonTotal || 0);
    }

    get formattedLostTotal() {
        return this.formatCurrency(this.reconciliationData.lostTotal || 0);
    }

    get formattedCreatedTotal() {
        return this.formatCurrency(this.reconciliationData.createdTotal || 0);
    }

    get formattedShiftedTotal() {
        const shiftedOpps = this.reconciliationData.shiftedOpportunities || [];
        const total = shiftedOpps.reduce((sum, opp) => sum + (opp.opportunity.Amount || 0), 0);
        return this.formatCurrency(total);
    }

    get formattedChangedTotal() {
        return this.formatCurrency(Math.abs(this.reconciliationData.changedTotal || 0));
    }

    get formattedChangedImpact() {
        return this.formatCurrencyWithSign(this.reconciliationData.changedTotal || 0);
    }

    get changedImpactClass() {
        const total = this.reconciliationData.changedTotal || 0;
        return total >= 0 ? 'category-impact positive' : 'category-impact negative';
    }

    // Has data checks
    get hasWonOpportunities() {
        return this.wonCount > 0;
    }

    get hasLostOpportunities() {
        return this.lostCount > 0;
    }

    get hasCreatedOpportunities() {
        return this.createdCount > 0;
    }

    get hasShiftedOpportunities() {
        return this.shiftedCount > 0;
    }

    get hasChangedOpportunities() {
        return this.changedCount > 0;
    }

    // Datatable columns
    get opportunityColumns() {
        return [
            { label: 'Opportunity Name', fieldName: 'opportunity.Name', type: 'text' },
            { label: 'Account', fieldName: 'opportunity.AccountName', type: 'text' },
            { label: 'Amount', fieldName: 'formattedAmount', type: 'text' },
            { label: 'Stage', fieldName: 'opportunity.StageName', type: 'text' },
            { label: 'Close Date', fieldName: 'opportunity.CloseDate', type: 'date-local' },
            { label: 'Delta', fieldName: 'formattedDelta', type: 'text' },
            { label: 'Details', fieldName: 'metadata', type: 'text', wrapText: true }
        ];
    }

    // Utility methods
    formatCurrency(amount) {
        if (amount === null || amount === undefined || isNaN(amount)) {
            return '$0';
        }
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(amount);
    }

    formatCurrencyWithSign(amount) {
        if (amount === null || amount === undefined || isNaN(amount) || amount === 0) {
            return '$0';
        }

        const formatted = this.formatCurrency(Math.abs(amount));
        return amount > 0 ? '+' + formatted : '−' + formatted.substring(1);
    }
}