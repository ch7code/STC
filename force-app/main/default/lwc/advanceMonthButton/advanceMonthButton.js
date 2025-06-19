// advanceMonthButton.js
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import advanceToNextMonth from '@salesforce/apex/ForecastManagerLWC.advanceToNextMonth';
import getCurrentForecastMonth from '@salesforce/apex/ForecastManagerLWC.getCurrentForecastMonth';
import checkAdminAccess from '@salesforce/apex/ForecastManagerLWC.checkAdminAccess';

export default class AdvanceMonthButton extends LightningElement {
    @track currentMonth = '';
    @track isLoading = false;
    @track isAdmin = false;

    connectedCallback() {
        this.loadCurrentMonth();
        this.checkUserAccess();
    }

    // Check if user has admin access
    async checkUserAccess() {
        try {
            this.isAdmin = await checkAdminAccess();
        } catch (error) {
            console.error('Error checking admin access:', error);
        }
    }

    // Load current forecast month
    async loadCurrentMonth() {
        try {
            this.isLoading = true;
            const result = await getCurrentForecastMonth();
            this.currentMonth = result || 'Not Set';
        } catch (error) {
            console.error('Error loading current month:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Advance to next month
    async handleAdvanceMonth() {
        if (!this.isAdmin) {
            this.showToast('Error', 'You do not have permission to advance the forecast month.', 'error');
            return;
        }

        try {
            this.isLoading = true;
            await advanceToNextMonth();
            await this.loadCurrentMonth();
            this.showToast('Success', 'Forecast month advanced successfully!', 'success');
        } catch (error) {
            const errorMessage = 'Error advancing month: ' + (error.body?.message || error.message);
            this.showToast('Error', errorMessage, 'error');
            console.error('Error advancing month:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Show toast message
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    // Computed properties
    get formattedCurrentMonth() {
        return this.currentMonth !== 'Not Set' ? `Current: ${this.currentMonth}` : 'No forecast month set';
    }

    get isButtonDisabled() {
        return this.isLoading || !this.isAdmin;
    }

    get buttonLabel() {
        return this.isLoading ? 'Processing...' : 'Advance to Next Month';
    }
}