import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getScheduleData from '@salesforce/apex/ShadowLWCGridController.getScheduleData';
import updateScheduleRecord from '@salesforce/apex/ShadowLWCGridController.updateScheduleRecord';

export default class ShadowLWCGrid extends LightningElement {
    @api recordId;
    @track scheduleData = {};
    @track hasData = false;
    @track isLoading = false;
    wiredScheduleResult;
    saveTimeout;

    @wire(getScheduleData, { recordId: '$recordId' })
    wiredScheduleData(result) {
        this.wiredScheduleResult = result;
        if (result.data) {
            this.scheduleData = result.data;
            this.hasData = true;
        } else if (result.error) {
            console.error('Error loading data:', result.error);
            this.showToast('Error', 'Error loading schedule data', 'error');
            this.hasData = false;
        }
    }

    // Getter that returns formatted dates for all month fields
    get getFormattedDate() {
        const formattedDates = {};
        
        // Process each month field (Month0__c through Month5__c)
        for (let i = 0; i <= 5; i++) {
            const fieldName = `Month${i}__c`;
            const monthValue = this.scheduleData[fieldName];
            formattedDates[fieldName] = this.formatDateToMmmYy(monthValue);
        }
        
        return formattedDates;
    }

    // Getter that calculates deltas between consecutive amounts
    get getDelta() {
        const deltas = {};
        
        // Calculate delta for each version (comparing with previous version)
        for (let i = 0; i <= 5; i++) {
            const currentAmount = parseFloat(this.scheduleData[`Amount${i}__c`]) || 0;
            const previousAmount = parseFloat(this.scheduleData[`Amount${i+1}__c`]) || 0;
            const delta = currentAmount - previousAmount;
            
            // Format delta with proper currency display
            if (delta === 0) {
                deltas[`delta${i}`] = '—';
            } else if (delta > 0) {
                deltas[`delta${i}`] = `+${Math.abs(delta).toLocaleString()}`;
            } else {
                deltas[`delta${i}`] = `-${Math.abs(delta).toLocaleString()}`;
            }
        }
        
        return deltas;
    }

    // ****************TESTING

    // Getter that returns CSS classes for delta styling
    get getDeltaClass() {
        const deltaClasses = {};
        
        for (let i = 0; i <= 5; i++) {
            const currentAmount = parseFloat(this.scheduleData[`Amount${i}__c`]) || 0;
            const previousAmount = parseFloat(this.scheduleData[`Amount${i+1}__c`]) || 0;
            const delta = currentAmount - previousAmount;
            
            if (delta > 0) {
                deltaClasses[`delta${i}`] = 'slds-text-color_success'; // Green for positive
            } else if (delta < 0) {
                deltaClasses[`delta${i}`] = 'slds-text-color_error'; // Red for negative
            } else {
                deltaClasses[`delta${i}`] = 'slds-text-color_weak'; // Gray for zero
            }
        }
        
        return deltaClasses;
    }

    // Helper method to convert yy/mm/dd format to mmm-yy format
    formatDateToMmmYy(dateString) {
        if (!dateString || dateString.trim() === '') {
            return '';
        }

        try {
            // Handle yy/mm/dd format (assuming the format is exactly like "25/03/15" for March 15, 2025)
            const parts = dateString.split('/');
            
            if (parts.length !== 3) {
                return dateString; // Return original if not in expected format
            }

            const [monthPart, dayPart, yearPart] = parts;
            
            // Convert 2-digit year to 4-digit (assuming 20xx for years 00-99)
            const year = parseInt(yearPart) < 50 ? `20${yearPart}` : `19${yearPart}`;
            const month = parseInt(monthPart);
            const day = parseInt(dayPart);

            // Validate month (1-12)
            if (month < 1 || month > 12) {
                return dateString; // Return original if invalid month
            }

            // Create date object
            const date = new Date(year, month - 1, day); // month is 0-indexed in Date constructor
            
            // Month abbreviations
            const monthNames = [
                'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
            ];
            
            const monthAbbr = monthNames[date.getMonth()];
            const yearAbbr = date.getFullYear().toString().slice(-2);
            
            return `${monthAbbr}-${yearAbbr}`;
            
        } catch (error) {
            console.warn('Error formatting date:', dateString, error);
            return dateString; // Return original string if parsing fails
        }
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        
        // Update local data immediately
        this.scheduleData = { ...this.scheduleData, [field]: value };
        
        // Debounce the save operation
        clearTimeout(this.saveTimeout);
        this.saveTimeout = setTimeout(() => {
            this.autoSave();
        }, 1000); // Save 1 second after user stops typing
    }

    async autoSave() {
        try {
            await updateScheduleRecord({ record: this.scheduleData });
            // Optionally show a subtle success indicator
            console.log('Auto-saved successfully');
        } catch (error) {
            console.error('Auto-save failed:', error);
            this.showToast('Error', 'Failed to save changes', 'error');
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}