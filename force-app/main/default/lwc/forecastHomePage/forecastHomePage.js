import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import advanceToNextMonth from '@salesforce/apex/ForecastManagerLWC.advanceToNextMonth';
import getCurrentForecastMonth from '@salesforce/apex/ForecastManagerLWC.getCurrentForecastMonth';
import checkAdminAccess from '@salesforce/apex/ForecastManagerLWC.checkAdminAccess';
import getDashboardData from '@salesforce/apex/ForecastManagerLWC.getDashboardData';
import getOpportunityChanges from '@salesforce/apex/ForecastManagerLWC.getOpportunityChanges';
import generateSimulationData from '@salesforce/apex/ForecastManagerLWC.generateSimulationData';
import resetToJanuary2025 from '@salesforce/apex/ForecastManagerLWC.resetToJanuary2025';
import cleanupSimulationData from '@salesforce/apex/ForecastManagerLWC.cleanupSimulationData';
import { wire } from 'lwc';
import getAnnualRevenueData from '@salesaforce/apex/ForecastDataService.getAnnualRevenueData';

export default class ForecastHomePage extends LightningElement {
    @track currentMonth = '';
    @track isLoading = false;
    @track isAdmin = false;
    @track error = '';
    @track dashboardData = {};
    @track showSimulationControls = false;
    @track opportunityChanges = [];
    @track showChangesDropdown = false;
    @track selectedYear = 2025;
    @track annualRevenueData = {};

    @wire(getAnnualRevenueData, { year: '$selectedYear' })
    wiredAnnualRevenue({ error, data }) {
    if (data) {
        this.annualRevenueData = data;
        console.log('Annual revenue data loaded for', this.selectedYear, ':', this.annualRevenueData);
    } else if (error) {
        console.error('Error loading annual revenue data:', error);
        this.annualRevenueData = {};
    }
}
    connectedCallback() {
        this.loadCurrentMonth();
        this.checkUserAccess();
        this.loadDashboardData();
        this.loadOpportunityChanges(); // Add this line

    }

    async loadOpportunityChanges() {
    try {
        const result = await getOpportunityChanges();
        this.opportunityChanges = result || [];
        console.log('Opportunity changes loaded:', this.opportunityChanges.length, 'changes found');
        console.log('Changes data:', this.opportunityChanges);
    } catch (error) {
        console.error('Error loading opportunity changes:', error);
        this.opportunityChanges = [];
    }
}

    async checkUserAccess() {
        try {
            this.isAdmin = await checkAdminAccess();
        } catch (error) {
            console.error('Error checking admin access:', error);
        }
    }

    async loadCurrentMonth() {
        try {
            this.isLoading = true;
            const result = await getCurrentForecastMonth();
            this.currentMonth = result || 'Not Set';
            this.error = '';
        } catch (error) {
            this.error = 'Error loading current month: ' + (error.body?.message || error.message);
            console.error('Error loading current month:', error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadDashboardData() {
        try {
            const result = await getDashboardData();
            this.dashboardData = result || {};
            console.log('Dashboard data loaded:', this.dashboardData);
        } catch (error) {
            console.error('Error loading dashboard data:', error);
            this.dashboardData = {};
        }
    }

    async handleAdvanceMonth() {
        if (!this.isAdmin) {
            this.showToast('Error', 'You do not have permission to advance the forecast month.', 'error');
            return;
        }

        try {
            this.isLoading = true;
            const result = await advanceToNextMonth();
            await this.delay(1000);
            await this.refreshAllData();
            
            const recordsUpdated = result.recordsUpdated || '0';
            const newMonth = result.newMonth || 'Unknown';
            const changedOpportunities = result.changedOpportunities || '0';
            const monthType = result.monthType || 'Normal';
            
            // Enhanced success message with market simulation details
            const message = `Forecast month advanced to ${newMonth}. ${recordsUpdated} records updated. ${monthType} Month: ${changedOpportunities} opportunities changed due to market conditions.`;
            
            this.showToast('Success', message, 'success');
                
        } catch (error) {
            this.error = 'Error advancing month: ' + (error.body?.message || error.message);
            this.showToast('Error', this.error, 'error');
            console.error('Error advancing month:', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleGenerateSimData() {
        if (!this.isAdmin) {
            this.showToast('Error', 'You do not have permission to generate simulation data.', 'error');
            return;
        }

        try {
            this.isLoading = true;
            const result = await generateSimulationData();
            
            await this.delay(1500); // Longer delay for complete setup
            await this.refreshAllData();
            
            const message = `Complete simulation setup! Created ${result.opportunitiesCreated} opportunities, ${result.accountsCreated} accounts, and ${result.snapshotsCreated} forecast snapshots. Pipeline: ${result.totalPipelineValue?.toLocaleString()}. Current month: ${result.currentForecastMonth}. Deleted ${result.opportunitiesDeleted} old opportunities, ${result.accountsDeleted} old accounts, ${result.snapshotsDeleted} old snapshots.`;
            this.showToast('Success', message, 'success');
            
        } catch (error) {
            this.error = 'Error generating simulation data: ' + (error.body?.message || error.message);
            this.showToast('Error', this.error, 'error');
            console.error('Error generating simulation data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleResetToJanuary() {
        if (!this.isAdmin) {
            this.showToast('Error', 'You do not have permission to reset data.', 'error');
            return;
        }

        try {
            this.isLoading = true;
            const result = await resetToJanuary2025();
            
            await this.delay(1000);
            await this.refreshAllData();
            
            const message = `Complete reset to Jan 2025! Deleted ${result.opportunitiesDeleted} opportunities, ${result.accountsDeleted} accounts, and ${result.snapshotsDeleted} snapshots. Ready for fresh simulation.`;
            this.showToast('Success', message, 'success');
            
        } catch (error) {
            this.error = 'Error resetting data: ' + (error.body?.message || error.message);
            this.showToast('Error', this.error, 'error');
            console.error('Error resetting data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleCleanupSimData() {
        // Now just calls the same method as reset
        await this.handleResetToJanuary();
    }

    handleToggleSimControls() {
        this.showSimulationControls = !this.showSimulationControls;
    }

    handleOpenReport() {
        const reportUrl = '/lightning/r/Report/00ORL000007vufl2AA/view';
        window.open(reportUrl, '_blank');
    }

    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    async refreshAllData() {
        try {
            await this.loadCurrentMonth();
            await this.delay(500);
            await this.loadDashboardDataFresh();
            await this.loadOpportunityChanges(); // Add this line

        } catch (error) {
            console.error('Error refreshing data:', error);
        }
    }

    async loadDashboardDataFresh() {
        try {
            // Force a fresh call to bypass any caching
            const result = await getDashboardData();
            this.dashboardData = result || {};
            console.log('Dashboard data refreshed:', this.dashboardData);
        } catch (error) {
            console.error('Error loading fresh dashboard data:', error);
            await this.loadDashboardData();
        }
    }

    // Remove methods we no longer need
    get hasOpportunityChanges() {
        return this.opportunityChanges && this.opportunityChanges.length > 0;
    }

    get changesToggleLabel() {
        const count = this.opportunityChanges ? this.opportunityChanges.length : 0;
        return this.showChangesDropdown ? `Hide Changes (${count})` : `Show Changes (${count})`;
    }

    handleToggleChanges() {
        this.showChangesDropdown = !this.showChangesDropdown;
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    get formattedCurrentMonth() {
        return this.currentMonth !== 'Not Set' ? this.currentMonth : 'No forecast month set';
    }

    get isButtonDisabled() {
        return this.isLoading || !this.isAdmin;
    }

    get simulationToggleLabel() {
        return this.showSimulationControls ? 'Hide Simulation Controls' : 'Show Simulation Controls';
    }

    get currentAmount() {
        return this.formatCurrency(this.dashboardData.currentMonth || 0);
    }

    get previousAmount1() {
        return this.formatCurrency(this.dashboardData.previousMonth1 || 0);
    }

    get previousAmount2() {
        return this.formatCurrency(this.dashboardData.previousMonth2 || 0);
    }

    get previousAmount3() {
        return this.formatCurrency(this.dashboardData.previousMonth3 || 0);
    }

    get previousAmount4() {
        return this.formatCurrency(this.dashboardData.previousMonth4 || 0);
    }

    get previousAmount5() {
        return this.formatCurrency(this.dashboardData.previousMonth5 || 0);
    }

    get delta1() {
        const current = this.dashboardData.currentMonth || 0;
        const previous = this.dashboardData.previousMonth1 || 0;
        return current - previous;
    }

    get delta2() {
        const month1 = this.dashboardData.previousMonth1 || 0;
        const month2 = this.dashboardData.previousMonth2 || 0;
        return month1 - month2;
    }

    get delta3() {
        const month2 = this.dashboardData.previousMonth2 || 0;
        const month3 = this.dashboardData.previousMonth3 || 0;
        return month2 - month3;
    }

    get delta4() {
        const month3 = this.dashboardData.previousMonth3 || 0;
        const month4 = this.dashboardData.previousMonth4 || 0;
        return month3 - month4;
    }

    get delta5() {
        const month4 = this.dashboardData.previousMonth4 || 0;
        const month5 = this.dashboardData.previousMonth5 || 0;
        return month4 - month5;
    }

    get formattedDelta1() {
        return this.formatDelta(this.delta1);
    }

    get formattedDelta2() {
        return this.formatDelta(this.delta2);
    }

    get formattedDelta3() {
        return this.formatDelta(this.delta3);
    }

    get formattedDelta4() {
        return this.formatDelta(this.delta4);
    }

    get formattedDelta5() {
        return this.formatDelta(this.delta5);
    }

    get delta1Class() {
        return this.getDeltaClass(this.delta1);
    }

    get delta2Class() {
        return this.getDeltaClass(this.delta2);
    }

    get delta3Class() {
        return this.getDeltaClass(this.delta3);
    }

    get delta4Class() {
        return this.getDeltaClass(this.delta4);
    }

    get delta5Class() {
        return this.getDeltaClass(this.delta5);
    }

    // NEW: Forward Pipeline getters
    get forwardPipelineData() {
        return this.dashboardData.forwardPipeline || {};
    }

    get forwardMonthLabels() {
        return this.forwardPipelineData.monthLabels || [];
    }

    get forwardMonthlyAmounts() {
        return this.forwardPipelineData.monthlyAmounts || [];
    }

    get totalForwardPipeline() {
        return this.formatCurrency(this.forwardPipelineData.totalForward || 0);
    }

    get hasForwardData() {
        return this.forwardMonthLabels.length > 0;
    }

    // NEW: Helper to get formatted amounts for each forward month
    get forwardMonthsDisplay() {
        const labels = this.forwardMonthLabels;
        const amounts = this.forwardMonthlyAmounts;
        
        if (!labels || !amounts || labels.length !== amounts.length) {
            return [];
        }

        return labels.map((label, index) => {
            // Convert "1/2025" to "Jan'25"
            const shortLabel = this.createShortLabel(label);
            
            return {
                label: label,
                shortLabel: shortLabel,
                amount: this.formatCurrency(amounts[index] || 0),
                rawAmount: amounts[index] || 0
            };
        });
    }
    // Year dropdown options
get yearOptions() {
    return [
        { label: '2025', value: 2025 },
        { label: '2026', value: 2026 },
        { label: '2027', value: 2027 },
        { label: '2028', value: 2028 }
    ];
}

// Annual revenue getters
get annualMonthLabels() {
    return this.annualRevenueData.monthLabels || [];
}

get annualMonthlyAmounts() {
    return this.annualRevenueData.monthlyAmounts || [];
}

get totalAnnualRevenue() {
    return this.formatCurrency(this.annualRevenueData.totalAnnual || 0);
}

get hasAnnualData() {
    return this.annualMonthLabels.length > 0 && this.annualRevenueData.totalAnnual > 0;
}

// Helper to get formatted amounts for each annual month
get annualMonthsDisplay() {
    const labels = this.annualMonthLabels;
    const amounts = this.annualMonthlyAmounts;
    
    if (!labels || !amounts || labels.length !== amounts.length) {
        return [];
    }

    return labels.map((label, index) => {
        // Convert "Jan 2025" to "Jan"
        const shortLabel = label.split(' ')[0];
        
        return {
            label: label,
            shortLabel: shortLabel,
            amount: this.formatCurrency(amounts[index] || 0),
            rawAmount: amounts[index] || 0
        };
    });
}

// Event handler for year change
handleYearChange(event) {
    this.selectedYear = parseInt(event.detail.value);
    console.log('Year changed to:', this.selectedYear);
}

    // Helper to create short month labels
    createShortLabel(monthYear) {
        try {
            // Input format: "1/2025"
            const parts = monthYear.split('/');
            if (parts.length !== 2) return monthYear;
            
            const monthNum = parseInt(parts[0]);
            const year = parts[1];
            
            const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                              'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            
            if (monthNum < 1 || monthNum > 12) return monthYear;
            
            // Return format: "Jan'25"
            return monthNames[monthNum - 1] + "'" + year.substring(2);
        } catch (e) {
            return monthYear; // Fallback to original
        }
    }

    formatCurrency(amount) {
        if (amount == null || amount === 0) return '$0';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(amount);
    }

    formatDelta(delta) {
        if (delta == null || delta === 0) return '$0';
        const sign = delta > 0 ? '+' : '';
        return sign + new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        }).format(delta);
    }

    getDeltaClass(delta) {
        const currentMonth = this.dashboardData.currentMonth || 0;
        const previousMonth1 = this.dashboardData.previousMonth1 || 0;
        const previousMonth2 = this.dashboardData.previousMonth2 || 0;
        const previousMonth3 = this.dashboardData.previousMonth3 || 0;
        const previousMonth4 = this.dashboardData.previousMonth4 || 0;
        const previousMonth5 = this.dashboardData.previousMonth5 || 0;
        
        // Don't color if comparing to zero (avoid excessive green)
        if (delta === this.delta1 && previousMonth1 === 0) return 'slds-text-color_default';
        if (delta === this.delta2 && previousMonth2 === 0) return 'slds-text-color_default';
        if (delta === this.delta3 && previousMonth3 === 0) return 'slds-text-color_default';
        if (delta === this.delta4 && previousMonth4 === 0) return 'slds-text-color_default';
        if (delta === this.delta5 && previousMonth5 === 0) return 'slds-text-color_default';
        
        // Only color significant changes (>$10K)
        if (Math.abs(delta) < 10000) return 'slds-text-color_default';
        
        if (delta > 0) return 'slds-text-color_success'; // Green for positive
        if (delta < 0) return 'slds-text-color_error';   // Red for negative
        return 'slds-text-color_default';                // Default for small changes
    }
}