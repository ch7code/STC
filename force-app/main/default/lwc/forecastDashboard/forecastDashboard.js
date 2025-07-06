import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getDashboardData from '@salesforce/apex/ForecastManagerLWC.getDashboardData';
import getCurrentForecastMonth from '@salesforce/apex/ForecastManagerLWC.getCurrentForecastMonth';
import advanceToNextMonth from '@salesforce/apex/ForecastManagerLWC.advanceToNextMonth';
import generateSimulationData from '@salesforce/apex/ForecastManagerLWC.generateSimulationData';
import getAnnualRevenueData from '@salesforce/apex/ForecastDataService.getAnnualRevenueData';

export default class ForecastDashboard extends LightningElement {
    @track currentForecastMonth = '';
    @track dashboardData = {};
    @track annualData = {};
    @track isLoading = false;
    @track showToast = false;
    @track toastMessage = '';
    @track toastVariant = 'success';
    @track selectedYear = '2025';

    wiredDashboardResult;
    wiredAnnualResult;

    yearOptions = [
        { label: '2024', value: '2024' },
        { label: '2025', value: '2025' },
        { label: '2026', value: '2026' },
        { label: '2027', value: '2027' }
    ];

    connectedCallback() {
        this.loadCurrentMonth();
    }

    async loadCurrentMonth() {
        try {
            // Force a fresh call to get current month
            this.currentForecastMonth = await getCurrentForecastMonth();
            console.log('Loaded current forecast month:', this.currentForecastMonth);
        } catch (error) {
            console.error('Error loading current month:', error);
            this.currentForecastMonth = '1/1/2025';
        }
    }

    @wire(getDashboardData)
    wiredDashboard(result) {
        this.wiredDashboardResult = result;
        if (result.data) {
            this.dashboardData = result.data;
            // Update current month from dashboard data if available
            if (result.data.currentForecastMonth) {
                this.currentForecastMonth = result.data.currentForecastMonth;
            }
        } else if (result.error) {
            console.error('Error loading dashboard data:', result.error);
        }
    }

    @wire(getAnnualRevenueData, { year: '$selectedYearNumber' })
    wiredAnnual(result) {
        this.wiredAnnualResult = result;
        if (result.data) {
            this.annualData = result.data;
        } else if (result.error) {
            console.error('Error loading annual data:', result.error);
        }
    }

    get selectedYearNumber() {
        return parseInt(this.selectedYear);
    }

    handleYearChange(event) {
        this.selectedYear = event.detail.value;
    }

    async handleAdvanceMonth() {
        this.isLoading = true;
        try {
            const result = await advanceToNextMonth();
            if (result.success === 'true') {
                this.currentForecastMonth = result.newMonth;
                this.showToastMessage(
                    `Advanced to ${result.newMonth}. ${result.monthType} month: ${result.wonOpportunities} won, ${result.lostOpportunities} lost, ${result.createdOpportunities || 0} created.`,
                    'success'
                );
                
                // Refresh all data
                await Promise.all([
                    refreshApex(this.wiredDashboardResult),
                    refreshApex(this.wiredAnnualResult)
                ]);
            }
        } catch (error) {
            this.showToastMessage('Error advancing month: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleGenerateSimulation() {
        this.isLoading = true;
        try {
            const result = await generateSimulationData();
            this.currentForecastMonth = result.currentForecastMonth;
            this.showToastMessage(
                `Simulation generated: ${result.accountsCreated} accounts, ${result.opportunitiesCreated} opportunities created.`,
                'success'
            );
            
            // Refresh all data
            await Promise.all([
                refreshApex(this.wiredDashboardResult),
                refreshApex(this.wiredAnnualResult)
            ]);
        } catch (error) {
            this.showToastMessage('Error generating simulation: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Computed properties for dashboard metrics
    get totalOpportunities() {
        return this.dashboardData.totalOpportunities || 0;
    }

    get formattedForwardTotal() {
        const total = this.dashboardData.forwardPipeline?.totalForward || 0;
        return this.formatCurrency(total);
    }

    get formattedAnnualTotal() {
        const total = this.annualData.totalAnnual || 0;
        return this.formatCurrency(total);
    }

get q1Total() {
        const months = this.annualData.monthlyAmounts || [];
        const q1 = Number(months[0] || 0) + Number(months[1] || 0) + Number(months[2] || 0);
        return this.formatCurrency(q1);
    }

    get q2Total() {
        const months = this.annualData.monthlyAmounts || [];
        const q2 = Number(months[3] || 0) + Number(months[4] || 0) + Number(months[5] || 0);
        return this.formatCurrency(q2);
    }

    get q3Total() {
        const months = this.annualData.monthlyAmounts || [];
        const q3 = Number(months[6] || 0) + Number(months[7] || 0) + Number(months[8] || 0);
        return this.formatCurrency(q3);
    }

    get q4Total() {
        const months = this.annualData.monthlyAmounts || [];
        const q4 = Number(months[9] || 0) + Number(months[10] || 0) + Number(months[11] || 0);
        return this.formatCurrency(q4);
    }

    get statusIcon() {
        return 'utility:success';
    }

    get statusVariant() {
        return 'success';
    }

    // Forward pipeline months
    get forwardPipelineMonths() {
        const labels = this.dashboardData.forwardPipeline?.monthLabels || [];
        const amounts = this.dashboardData.forwardPipeline?.monthlyAmounts || [];
        
        return labels.map((label, index) => ({
            key: 'forward-' + index,
            label: label,
            formattedAmount: this.formatCurrency(amounts[index] || 0)
        }));
    }

    // Annual months
    get annualMonths() {
        const labels = this.annualData.monthLabels || [];
        const amounts = this.annualData.monthlyAmounts || [];
        
        return labels.map((label, index) => ({
            key: 'annual-' + index,
            label: label.replace(this.selectedYear, '').trim(),
            formattedAmount: this.formatCurrency(amounts[index] || 0)
        }));
    }

    // Historical versions
    get historicalVersions() {
        return [
            { key: 'v0', label: 'Current', formattedAmount: this.formatCurrency(this.dashboardData.currentMonth || 0) },
            { key: 'v1', label: 'M-1', formattedAmount: this.formatCurrency(this.dashboardData.previousMonth1 || 0) },
            { key: 'v2', label: 'M-2', formattedAmount: this.formatCurrency(this.dashboardData.previousMonth2 || 0) },
            { key: 'v3', label: 'M-3', formattedAmount: this.formatCurrency(this.dashboardData.previousMonth3 || 0) },
            { key: 'v4', label: 'M-4', formattedAmount: this.formatCurrency(this.dashboardData.previousMonth4 || 0) },
            { key: 'v5', label: 'M-5', formattedAmount: this.formatCurrency(this.dashboardData.previousMonth5 || 0) }
        ];
    }

    get historicalPadding() {
        return Array(6).fill().map((_, i) => ({ key: 'h-pad-' + i }));
    }

    // Monthly deltas
    get monthlyDeltas() {
        const deltas = [];
        const versions = [
            this.dashboardData.currentMonth || 0,
            this.dashboardData.previousMonth1 || 0,
            this.dashboardData.previousMonth2 || 0,
            this.dashboardData.previousMonth3 || 0,
            this.dashboardData.previousMonth4 || 0,
            this.dashboardData.previousMonth5 || 0
        ];

        for (let i = 0; i < versions.length - 1; i++) {
            const delta = versions[i] - versions[i + 1];
            deltas.push({
                key: 'delta-' + i,
                label: i === 0 ? 'M0-M1' : `M${i}-M${i+1}`,
                formattedDelta: this.formatCurrencyDelta(delta),
                valueClass: delta >= 0 ? 'compact-value trend-positive' : 'compact-value trend-negative'
            });
        }

        return deltas;
    }

    get deltasPadding() {
        return Array(7).fill().map((_, i) => ({ key: 'd-pad-' + i }));
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

    formatCurrencyDelta(amount) {
        if (amount === null || amount === undefined || isNaN(amount) || amount === 0) {
            return '$0';
        }

        const formatted = this.formatCurrency(Math.abs(amount));
        return amount > 0 ? '+' + formatted : '−' + formatted.substring(1);
    }

    showToastMessage(message, variant) {
        this.toastMessage = message;
        this.toastVariant = variant;
        this.showToast = true;
        setTimeout(() => {
            this.showToast = false;
        }, 5000);
    }

    hideToast() {
        this.showToast = false;
    }

    get toastClass() {
        return `slds-notify slds-notify_toast slds-theme_${this.toastVariant}`;
    }
}