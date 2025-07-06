// pipelineMath.js
import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPipelineMath from '@salesforce/apex/PipelineMathController.getPipelineMath';
import getCurrentForecastMonth from '@salesforce/apex/ForecastManagerLWC.getCurrentForecastMonth';

export default class PipelineMath extends LightningElement {
    @track currentDate = new Date(2025, 1, 1); // Default fallback
    @track forecastMonthStr = '';
    @track mathData = {};
    @track includeWonRevenue = false; // Toggle state
    
    isLoading = true;
    error;
    
    // Track wired result for refreshApex
    wiredMathResult;

    connectedCallback() {
        this.loadCurrentForecastMonth();
    }

    async loadCurrentForecastMonth() {
        try {
            const data = await getCurrentForecastMonth();
            if (data && data !== this.forecastMonthStr) {
                this.forecastMonthStr = data;
                this.updateCurrentDate(data);
                console.log('Pipeline Math: Forecast month updated to', data);
            }
        } catch (error) {
            console.error('Pipeline Math: Error loading forecast month:', error);
        }
    }

    @wire(getPipelineMath, { 
        year: '$currentYear', 
        month: '$currentMonth',
        includeWonRevenue: '$includeWonRevenue'
    })
    wiredPipelineMath(result) {
        this.wiredMathResult = result;
        this.isLoading = false;
        
        if (result.data) {
            this.mathData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.mathData = {};
        }
    }

    updateCurrentDate(forecastMonthStr) {
        try {
            const dateParts = forecastMonthStr.split('/');
            if (dateParts.length === 3) {
                const month = parseInt(dateParts[0]) - 1;
                const day = parseInt(dateParts[1]);
                const year = parseInt(dateParts[2]);
                
                const newDate = new Date(year, month, day);
                
                if (newDate.getMonth() !== this.currentDate.getMonth() || 
                    newDate.getFullYear() !== this.currentDate.getFullYear()) {
                    
                    this.currentDate = newDate;
                    this.refreshMathData();
                }
            }
        } catch (error) {
            console.error('Error parsing forecast month:', error);
        }
    }

    async refreshMathData() {
        try {
            this.isLoading = true;
            await refreshApex(this.wiredMathResult);
        } catch (error) {
            console.error('Error refreshing math data:', error);
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

    get cardTitle() {
        const mode = this.includeWonRevenue ? 'Business View' : 'Sales View';
        return `Pipeline Math - ${this.mathData.analysisMonth || 'Loading...'} (${mode})`;
    }

    get toggleLabel() {
        return this.includeWonRevenue ? 'Include Won Revenue' : 'Exclude Won Revenue';
    }

    get toggleVariant() {
        return this.includeWonRevenue ? 'brand' : 'neutral';
    }

    // Handle toggle change
    handleToggleChange() {
        this.includeWonRevenue = !this.includeWonRevenue;
        console.log('Toggle changed to:', this.includeWonRevenue);
    }

    get forwardPeriod() {
        return this.mathData.forwardPeriod || '';
    }

    // Summary metrics
    get formattedPrevious() {
        return this.formatCurrency(this.mathData.forward12MPrevious || 0);
    }

    get formattedCurrent() {
        return this.formatCurrency(this.mathData.forward12MCurrent || 0);
    }

    get formattedChange() {
        return this.formatCurrencyWithSign(this.mathData.forward12MChange || 0);
    }

    get changeClass() {
        const change = this.mathData.forward12MChange || 0;
        return change >= 0 ? 'metric-value positive' : 'metric-value negative';
    }

    get formattedReconciliation() {
        return this.formatCurrencyWithSign(this.mathData.reconciliationCheck || 0);
    }

    get reconciliationClass() {
        const reconciliation = this.mathData.reconciliationCheck || 0;
        return reconciliation >= 0 ? 'metric-value positive' : 'metric-value negative';
    }

    get reconciliationIcon() {
        return this.mathData.isBalanced ? 'utility:success' : 'utility:warning';
    }

    get reconciliationVariant() {
        return this.mathData.isBalanced ? 'success' : 'warning';
    }

    get reconciliationStatus() {
        return this.mathData.isBalanced ? 'Balanced' : 'Check Required';
    }

    // Category totals
    get formattedRedTotal() {
        return this.formatCurrencyWithSign(this.mathData.redTotal || 0);
    }

    get formattedGreenTotal() {
        return this.formatCurrencyWithSign(this.mathData.greenTotal || 0);
    }

    get formattedGrayTotal() {
        return this.formatCurrencyWithSign(this.mathData.grayTotal || 0);
    }

    // Category items with formatting
    get redItems() {
        return this.processItems(this.mathData.redItems || []);
    }

    get greenItems() {
        return this.processItems(this.mathData.greenItems || []);
    }

    get grayItems() {
        return this.processItems(this.mathData.grayItems || []);
    }

processItems(items) {
    // First sort by absolute impact (descending)
    const sortedItems = [...items].sort((a, b) => {
        const absA = Math.abs(a.forwardImpact || 0);
        const absB = Math.abs(b.forwardImpact || 0);
        return absB - absA; // Descending order
    });
    
    // Then add formatting
    return sortedItems.map(item => ({
        ...item,
        formattedAmount: this.formatCurrency(item.currentAmount || 0),
        formattedImpact: this.formatCurrencyWithSign(item.forwardImpact || 0)
    }));
}

    // Has items checks
    get hasRedItems() {
        return (this.mathData.redItems || []).length > 0;
    }

    get hasGreenItems() {
        return (this.mathData.greenItems || []).length > 0;
    }

    get hasGrayItems() {
        return (this.mathData.grayItems || []).length > 0;
    }

    // Equation styling
    get reconciliationEquationClass() {
        return this.mathData.isBalanced ? 'equation-value balanced' : 'equation-value unbalanced';
    }

    get changeEquationClass() {
        const change = this.mathData.forward12MChange || 0;
        return change >= 0 ? 'equation-value positive' : 'equation-value negative';
    }
    get redItems() {
    return this.processItems(this.mathData.redItems || []);
}

get greenItems() {
    return this.processItems(this.mathData.greenItems || []);
}

get grayItems() {
    return this.processItems(this.mathData.grayItems || []);
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