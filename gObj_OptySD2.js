const fs = require("fs");
const path = require("path");

// Define the custom object metadata
const objectName = "Opty_Sd2__c"; // Updated object name
const objectFolder = path.join("force-app", "main", "default", "objects", objectName);
const fieldsFolder = path.join(objectFolder, "fields");

// Ensure folders exist
fs.mkdirSync(fieldsFolder, { recursive: true });

// Create Object Metadata XML
const objectXML = `<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Opty Sd2</label>
    <pluralLabel>Opty Sd2s</pluralLabel>
    <nameField>
        <type>AutoNumber</type>
        <label>Opty Sd2 Number</label>
        <displayFormat>A-{0000000}</displayFormat>
    </nameField>
    <deploymentStatus>Deployed</deploymentStatus>
    <sharingModel>ControlledByParent</sharingModel> <!-- Fixed: Master-Detail must use this -->
</CustomObject>`;

// Check if directory exists, if not, create it
fs.writeFileSync(path.join(objectFolder, `${objectName}.object-meta.xml`), objectXML);

// Define fields metadata
const fields = [
    { name: "Start_Date__c", label: "Start Date", type: "Date" },
    { name: "Amount__c", label: "Amount", type: "Currency", scale: 2, precision: 16 },
    { name: "Period_of_Performance__c", label: "Period of Performance", type: "Number", precision: 5, scale: 0 },
    { 
        name: "Opportunity__c", 
        label: "Opportunity", 
        type: "MasterDetail", 
        referenceTo: "Opportunity",
        relationshipName: "OptySd2_Opportunity" // Fixed: Added required relationshipName
    },
    { 
        name: "Year_Month_Formatted__c", 
        label: "Year Month Formatted", 
        type: "Formula", 
        returnType: "Text", 
        formula: 'TEXT(YEAR(Start_Date__c) - 2000) & "-" & RIGHT("0" & TEXT(MONTH(Start_Date__c)), 2)' // Fixed: Removed length
    }
];

// Allowed Salesforce field types
const validFieldTypes = ["AutoNumber", "Text", "Date", "Currency", "Number", "MasterDetail", "Formula"];

// Create fields metadata XML files
fields.forEach(field => {
    if (!validFieldTypes.includes(field.type)) {
        console.error(`❌ ERROR: Invalid field type "${field.type}" for field "${field.name}"`);
        return;
    }

    let fieldXML = `<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>${field.name}</fullName>
    <label>${field.label}</label>`;

    if (field.type === "Formula") {
        fieldXML += `\n    <type>${field.returnType}</type>\n    <formula>${field.formula}</formula>`;
    } else {
        fieldXML += `\n    <type>${field.type}</type>`;
    }

    if (field.type === "Currency") {
        fieldXML += `\n    <scale>${field.scale}</scale>\n    <precision>${field.precision}</precision>`;
    }
    if (field.type === "Number") {
        fieldXML += `\n    <precision>${field.precision}</precision>\n    <scale>${field.scale}</scale>`;
    }
    if (field.type === "MasterDetail") {
        fieldXML += `\n    <referenceTo>${field.referenceTo}</referenceTo>\n    <relationshipName>${field.relationshipName}</relationshipName>`;
    }

    fieldXML += `\n</CustomField>`;

    // Avoid hidden/system files like desktop.ini
    if (!field.name.includes('desktop.ini')) {
        fs.writeFileSync(path.join(fieldsFolder, `${field.name}.field-meta.xml`), fieldXML);
    }
});

console.log("✅ Object and fields created successfully!");
