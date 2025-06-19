import { LightningElement, wire, track } from 'lwc';
import getOpportunityChanges from '@salesforce/apex/OpportunityChangesController.getOpportunityChanges';

export default class OpportunityChanges extends LightningElement {
    @track opportunityData = [];
    @track error;
    @track isLoading = true;

    columns = [
        {
            label: 'Account',
            fieldName: 'accountName',
            type: 'text'
        },
        {
            label: 'Opportunity',
            fieldName: 'opportunityName',
            type: 'text'
        },
        {
            label: 'Stage',
            fieldName: 'stageName',
            type: 'text',
            cellAttributes: {
                class: { fieldName: 'stageClass' }
            }
        },
        {
            label: 'Amount Before',
            fieldName: 'amountBefore',
            type: 'currency',
            typeAttributes: {
                currencyCode: 'USD'
            }
        },
        {
            label: 'Amount After',
            fieldName: 'amountAfter',
            type: 'currency',
            typeAttributes: {
                currencyCode: 'USD'
            }
        },
        {
            label: 'Change Type',
            fieldName: 'changeType',
            type: 'text',
            cellAttributes: {
                class: { fieldName: 'changeClass' }
            }
        }
    ];

    @wire(getOpportunityChanges)
    wiredOpportunityChanges({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.opportunityData = data.map(opp => ({
                ...opp,
                stageClass: this.getStageClass(opp.stageName),
                changeClass: this.getChangeClass(opp.changeType)
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.opportunityData = [];
        }
    }

    getStageClass(stage) {
        if (stage === 'Closed Won') {
            return 'slds-text-color_success slds-text-title_bold';
        } else if (stage === 'Closed Lost') {
            return 'slds-text-color_error slds-text-title_bold';
        }
        return 'slds-text-color_default';
    }

    getChangeClass(changeType) {
        if (changeType === 'Closed Won') {
            return 'slds-text-color_success';
        } else if (changeType === 'Closed Lost') {
            return 'slds-text-color_error';
        } else if (changeType === 'Date Shifted') {
            return 'slds-text-color_weak';
        }
        return 'slds-text-color_default';
    }

    get hasData() {
        return this.opportunityData && this.opportunityData.length > 0;
    }

    get noDataMessage() {
        return 'No opportunity changes found for the last month.';
    }
}