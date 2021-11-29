#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

SALESFORCE_USERNAME=${SALESFORCE_USERNAME:-$1}
SALESFORCE_PASSWORD=${SALESFORCE_PASSWORD:-$2}
CONSUMER_KEY=${CONSUMER_KEY:-$3}
CONSUMER_PASSWORD=${CONSUMER_PASSWORD:-$4}
SECURITY_TOKEN=${SECURITY_TOKEN:-$5}
SALESFORCE_INSTANCE=${SALESFORCE_INSTANCE:-"https://login.salesforce.com"}

if [ -z "$SALESFORCE_USERNAME" ]
then
     logerror "SALESFORCE_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SALESFORCE_PASSWORD" ]
then
     logerror "SALESFORCE_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


if [ -z "$CONSUMER_KEY" ]
then
     logerror "CONSUMER_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$CONSUMER_PASSWORD" ]
then
     logerror "CONSUMER_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$SECURITY_TOKEN" ]
then
     logerror "SECURITY_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Login with sfdx CLI"
docker exec sfdx-cli sh -c "sfdx sfpowerkit:auth:login -u \"$SALESFORCE_USERNAME\" -p \"$SALESFORCE_PASSWORD\" -r \"$SALESFORCE_INSTANCE\" -s \"$SECURITY_TOKEN\""

log "Now login to SFDC and create an account with name Tesla (also make sure Account is part of CDC, see https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-cdc-source#enable-change-data-capture in README"
check_if_continue

log "Creating Salesforce CDC Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.salesforce.SalesforceCdcSourceConnector",
                    "kafka.topic": "sfdc-cdc-accounts",
                    "tasks.max": "1",
                    "curl.logging": "true",
                    "salesforce.instance" : "'"$SALESFORCE_INSTANCE"'",
                    "salesforce.cdc.name" : "AccountChangeEvent",
                    "salesforce.username" : "'"$SALESFORCE_USERNAME"'",
                    "salesforce.password" : "'"$SALESFORCE_PASSWORD"'",
                    "salesforce.password.token" : "'"$SECURITY_TOKEN"'",
                    "salesforce.consumer.key" : "'"$CONSUMER_KEY"'",
                    "salesforce.consumer.secret" : "'"$CONSUMER_PASSWORD"'",
                    "salesforce.initial.start" : "all",
                    "connection.max.message.size": "10048576",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/salesforce-cdc-source/config | jq .



sleep 10

log "Verify we have received the data in sfdc-cdc-accounts topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic sfdc-cdc-accounts --from-beginning --max-messages 1

# {
#     "ARR__c": "0",
#     "Account_Count__c": null,
#     "Account_Coverage_Type__c": null,
#     "Account_Level__c": null,
#     "Account_Manager__c": null,
#     "Account_Priority__c": null,
#     "Account_Revenue_Band__c": null,
#     "Active_Opps_Rollup__c": 0.0,
#     "Adoption_Phase__c": null,
#     "Adoption_Stage__c": null,
#     "AnnualRevenue": null,
#     "Annual_Revenue_Band__c": null,
#     "Annual_Revenue_Override__c": null,
#     "Auto_Data_Balancer_Adoption_Date_X__c": null,
#     "Auto_Data_Balancer_Adoption_Date__c": null,
#     "Auto_Data_Balancer_User__c": "No",
#     "BVC_Engagement_Date__c": null,
#     "BenchMark__c": false,
#     "BillingAddress": {
#         "City": "Cupertino",
#         "Country": "United States",
#         "GeocodeAccuracy": null,
#         "Latitude": null,
#         "Longitude": null,
#         "PostalCode": "95014",
#         "State": "California",
#         "Street": "1 Tesla Park Way"
#     },
#     "BillingCity": null,
#     "BillingCountry": null,
#     "BillingCountryCode": null,
#     "BillingGeocodeAccuracy": null,
#     "BillingLatitude": null,
#     "BillingLongitude": null,
#     "BillingPostalCode": null,
#     "BillingState": null,
#     "BillingStateCode": null,
#     "BillingStreet": null,
#     "C3_Adoption_Date_X__c": null,
#     "C3_Adoption_Date__c": null,
#     "C3_User__c": "No",
#     "CAB_Member__c": false,
#     "CCP_Users__c": null,
#     "CSAT_PS__c": null,
#     "CSAT_Support__c": null,
#     "CSAT_Training__c": null,
#     "ChangeEventHeader": {
#         "changeOrigin": "com/salesforce/api/soap/53.0;client=SfdcInternalAPI/",
#         "changeType": "CREATE",
#         "changedFields": [],
#         "commitNumber": 10903128200158,
#         "commitTimestamp": 1638205319000,
#         "commitUser": "0053a00000L9RsbAAF",
#         "entityName": "Account",
#         "recordIds": [
#             "0015500001NPDfcAAH"
#         ],
#         "sequenceNumber": 1,
#         "transactionKey": "0002c4c0-72a1-860e-bccf-8149bad2186b"
#     },
#     "Cloudy_Account_1__c": false,
#     "Company_HQ_Country__c": null,
#     "Confluent_Cloud_Adoption_Date__c": null,
#     "Confluent_Cloud_User__c": "No",
#     "Confluent_Open_Source_Connectors__c": null,
#     "Confluent_Product_Usage__c": null,
#     "Confluent_Program_of_Interest__c": null,
#     "Confluent_Proprietary_Connectors__c": null,
#     "Connectors_in_Use__c": null,
#     "Count__c": null,
#     "CreatedById": "0053a00000L9RsbAAF",
#     "CreatedDate": 1638205319000,
#     "Created_through_Lead_Conversion__c": false,
#     "CurrencyIsoCode": "USD",
#     "Current_MDF_Balance__c": null,
#     "Current_Subscription_Customer__c": null,
#     "Custom_Contract_Terms__c": null,
#     "Customer_360_Last_Updated__c": null,
#     "Customer_Cloud_Environments__c": null,
#     "Customer_Health_Overall__c": null,
#     "Customer_Solution_Owner__c": null,
#     "DNBoptimizer__DNB_D_U_N_S_Number__c": null,
#     "DNBoptimizer__DnBCompanyRecord__c": null,
#     "DNBoptimizer__Number_Of_Opportunity__c": 0.0,
#     "DO_Annual_Revenue__c": null,
#     "DO_Employees__c": null,
#     "DO_HQ_City__c": null,
#     "DO_HQ_Country__c": null,
#     "DO_HQ_Postal_Code__c": null,
#     "DO_HQ_State__c": null,
#     "DO_HQ_Street__c": null,
#     "DO_Industry__c": null,
#     "DSCORGPKG__Conflict__c": null,
#     "DSCORGPKG__DO_3yr_Employees_Growth__c": null,
#     "DSCORGPKG__DO_3yr_Sales_Growth__c": null,
#     "DSCORGPKG__DeletedFromDiscoverOrg__c": "false",
#     "DSCORGPKG__DiscoverOrg_Created_On__c": null,
#     "DSCORGPKG__DiscoverOrg_First_Update__c": null,
#     "DSCORGPKG__DiscoverOrg_FullCountryName__c": null,
#     "DSCORGPKG__DiscoverOrg_ID__c": null,
#     "DSCORGPKG__DiscoverOrg_LastUpdate__c": null,
#     "DSCORGPKG__DiscoverOrg_State_Full_Name__c": null,
#     "DSCORGPKG__DiscoverOrg_Technologies__c": null,
#     "DSCORGPKG__Exclude_Update__c": false,
#     "DSCORGPKG__External_DiscoverOrg_Id__c": null,
#     "DSCORGPKG__Fiscal_Year_End__c": null,
#     "DSCORGPKG__Fortune_Rank__c": null,
#     "DSCORGPKG__ITOrgChart__c": null,
#     "DSCORGPKG__IT_Budget__c": 0.0,
#     "DSCORGPKG__IT_Employees__c": null,
#     "DSCORGPKG__Lead_Source__c": "None",
#     "DSCORGPKG__Locked_By_User__c": null,
#     "DSCORGPKG__NAICS_Codes__c": null,
#     "DSCORGPKG__Ownership__c": null,
#     "DSCORGPKG__SIC_Codes__c": null,
#     "DSG_Favored_Account__c": false,
#     "DUNS_Number__c": null,
#     "DUNS_Parent__c": null,
#     "D_B_Annual_Revenue__c": null,
#     "D_B_Global_Ultimate_DUNS_Number__c": null,
#     "D_B_Number_of_Employees__c": null,
#     "D_B_Parent_DUNS_Number__c": null,
#     "Description": null,
#     "District__c": null,
#     "Domain__c": null,
#     "Domestic_Ultimate_Account__c": null,
#     "Dummy_Workflow_Field__c": null,
#     "EAM_Owner__c": null,
#     "EBV_Rollup__c": "0",
#     "Employee_Size_Override__c": null,
#     "Employee_Size_Tier__c": null,
#     "Exclude_from_Account_Type_Logic__c": false,
#     "Exec_Sponser_NEW__c": null,
#     "Exec_Sponsor__c": null,
#     "Executed_Confluent_Agreements__c": null,
#     "Exemption_from_Opp_Owner_Mismatch__c": false,
#     "Federal_US_Only__c": false,
#     "Fee_Waiver__c": null,
#     "FirstName": null,
#     "First_Annual_Subscription_Close_Date__c": null,
#     "First_Cloud_Subscription_Date__c": null,
#     "First_Subscription_Close_Date__c": null,
#     "Focus_Account__c": false,
#     "Geo_Region__c": null,
#     "Geo__c": null,
#     "Global_2000_Rank__c": null,
#     "Global_Ultimate_Account__c": null,
#     "Id": "0015500001NPDfcAAH",
#     "Industry": null,
#     "Initial_Subscription_Start_Date__c": null,
#     "IsParent__c": false,
#     "JigsawCompanyId": null,
#     "KSQL_Adoption_Date_X__c": null,
#     "KSQL_Adoption_Date__c": null,
#     "KSQL__c": "No",
#     "Kafka_Connect_Adoption_Date_X__c": null,
#     "Kafka_Connect_Adoption_Date__c": null,
#     "Kafka_Connect__c": "No",
#     "Kafka_Server_Adoption_Date__c": null,
#     "Kafka_Server_User__c": "No",
#     "Kafka_Streams_Adoption_Date_X__c": null,
#     "Kafka_Streams_Adoption_Date__c": null,
#     "Kafka_Streams__c": "No",
#     "LAX_Account_Tier_Report__c": null,
#     "LID__LinkedIn_Company_Id__c": null,
#     "LastModifiedById": "0053a00000L9RsbAAF",
#     "LastModifiedDate": 1638205319000,
#     "LastName": null,
#     "Last_QBR_Date__c": null,
#     "LeanData__LD_EmailDomain__c": null,
#     "LeanData__LD_EmailDomains__c": null,
#     "LeanData__Reporting_Customer__c": false,
#     "LeanData__Reporting_Has_Opportunity__c": false,
#     "LeanData__Reporting_Last_Marketing_Touch_Date__c": null,
#     "LeanData__Reporting_Last_Sales_Touch_Date__c": null,
#     "LeanData__Reporting_Recent_Marketing_Touches__c": null,
#     "LeanData__Reporting_Target_Account_Number__c": null,
#     "LeanData__Reporting_Target_Account__c": false,
#     "LeanData__Reporting_Total_Leads_and_Contacts__c": null,
#     "LeanData__Reporting_Total_Marketing_Touches__c": null,
#     "LeanData__Routing_Action__c": null,
#     "LeanData__SLA__c": null,
#     "LeanData__Scenario_1_Owner__c": null,
#     "LeanData__Scenario_2_Owner__c": null,
#     "LeanData__Scenario_3_Owner__c": null,
#     "LeanData__Scenario_4_Owner__c": null,
#     "LeanData__Search__c": "xzqehlrmifvd w:Tesla.com Tesla a:1-95014",
#     "LeanData__Tag__c": null,
#     "Maturity_Level__c": null,
#     "Max_Subscription_End_Date_Gold__c": null,
#     "Max_Subscription_End_Date_PLA__c": null,
#     "Membership_End_Date__c": null,
#     "Membership_Fee_Paid__c": null,
#     "Membership_Start_Date__c": null,
#     "Mirror_Maker_Adoption_Date_X__c": null,
#     "Mirror_Maker_Adoption_Date__c": null,
#     "Mirror_Maker_User__c": "No",
#     "NPS__c": null,
#     "NS_SFDC_Billing_Address_ID__c": null,
#     "NS_SFDC_Shipping_Address_ID__c": null,
#     "Name": "Tesla",
#     "Netsuite_Currency__c": "US Dollar",
#     "Netsuite_Customer_ID__c": null,
#     "Netsuite_Subsidiary__c": "Confluent, Inc",
#     "New_Logo_Date__c": null,
#     "New_Partner_Agreement_Signed__c": null,
#     "Next_QBR_Date__c": null,
#     "Nominate_for_Reference__c": false,
#     "NumberOfEmployees": null,
#     "Opp_Renewal_Sum_Rollup__c": "0",
#     "Opps_Amount_Rollup__c": "0",
#     "Opps_Count_Rollup__c": 0.0,
#     "OwnerId": "0053a00000L9RsbAAF",
#     "Owner_Active__c": null,
#     "PAB__c": false,
#     "ParentId": null,
#     "Partner_Account_Status__c": null,
#     "Partner_Agreement_Signed_Contact__c": null,
#     "Partner_Agreement__c": false,
#     "Partner_Category__c": null,
#     "Partner_Classification_Tier__c": null,
#     "Partner_Interest_Category__c": null,
#     "Partner_Interest__c": null,
#     "Partner_Kafka_Connector_Interest__c": null,
#     "Partner_Level__c": null,
#     "Partner_Pillar__c": null,
#     "Partner_Prioritization_Ranking__c": null,
#     "Partner_Top_Verticals__c": null,
#     "Payment_Invoice__c": null,
#     "Phone": "+1 408-996-1010",
#     "Platinum_Subscription_on_Open_Renewals__c": "0",
#     "Primary_Geo_Sell__c": null,
#     "Primary_LAX_Account_Tier__c": false,
#     "Primary_Partner_Business__c": null,
#     "Private_Clouds__c": null,
#     "Procurement_Tool__c": null,
#     "Product_Adoption_Date__c": null,
#     "Product_Adoption_Filled__c": null,
#     "Product_Adoption_Implemented_Date_Time__c": null,
#     "Product_Version__c": null,
#     "Production_Launch_Date__c": null,
#     "Products_Used__c": null,
#     "Public_Clouds__c": null,
#     "Public_Private_Clouds__c": null,
#     "Publicly_Reference_able_Customer__c": false,
#     "Ready_To_Sync__c": false,
#     "RecordTypeId": "0123a0000000MuIAAU",
#     "Region_New_Backend__c": "US - California",
#     "Region__c": null,
#     "RelaywareID__c": null,
#     "Renewal_Language__c": null,
#     "Renewal_Risk_Status__c": null,
#     "ReplayId": "4290851",
#     "Replicator_Kafka_Connect_Adoption_Date_X__c": null,
#     "Replicator_Kafka_Connect_Adoption_Date__c": null,
#     "Replicator_Kafka_Connect_User__c": "No",
#     "Rest_Proxy_Adoption_Date_X__c": null,
#     "Rest_Proxy_Adoption_Date__c": null,
#     "Rest_Proxy_User__c": "No",
#     "Restricted_Account__c": false,
#     "Role_Type__c": null,
#     "Route_Leads_to_Account_Owner__c": false,
#     "SBQQ__AssetQuantitiesCombined__c": false,
#     "SBQQ__CoTermedContractsCombined__c": false,
#     "SBQQ__CoTerminationEvent__c": null,
#     "SBQQ__ContractCoTermination__c": "Never",
#     "SBQQ__DefaultOpportunity__c": null,
#     "SBQQ__IgnoreParentContractedPrices__c": false,
#     "SBQQ__PreserveBundle__c": true,
#     "SBQQ__PriceHoldEnd__c": null,
#     "SBQQ__RenewalModel__c": "Contract Based",
#     "SBQQ__RenewalPricingMethod__c": "Same",
#     "SBQQ__TaxExempt__c": "No",
#     "Sales_Engineer_SE__c": null,
#     "Salutation": null,
#     "Schema_Registry_Adoption_Date_X__c": null,
#     "Schema_Registry_Adoption_Date__c": null,
#     "Schema_Registry_User__c": "No",
#     "Security_Plug_Ins_Adoption_Date_X__c": null,
#     "Security_Plug_Ins_Adoption_Date__c": null,
#     "Security_Plug_Ins__c": "No",
#     "Sequoia_Company__c": false,
#     "Services_Balance__c": null,
#     "ShippingAddress": {
#         "City": "paris",
#         "Country": "France",
#         "GeocodeAccuracy": null,
#         "Latitude": null,
#         "Longitude": null,
#         "PostalCode": "78666",
#         "State": "Alsace",
#         "Street": "test"
#     },
#     "ShippingCity": null,
#     "ShippingCountry": null,
#     "ShippingCountryCode": null,
#     "ShippingGeocodeAccuracy": null,
#     "ShippingLatitude": null,
#     "ShippingLongitude": null,
#     "ShippingPostalCode": null,
#     "ShippingState": null,
#     "ShippingStateCode": null,
#     "ShippingStreet": null,
#     "Subscription_End_Date_Cloud_ACV__c": null,
#     "Subscription_End_Date__c": null,
#     "Subscription_Tier__c": null,
#     "Support_Onboarding_Date__c": null,
#     "Sync_Error__c": null,
#     "Sync_Status__c": null,
#     "Sync_To_Relayware__c": false,
#     "Technical_Account_Manager__c": null,
#     "Territories__c": null,
#     "Theatre__c": null,
#     "Ticket_Opened_Last_3_Months__c": null,
#     "Tickets_Opened_Last_6_Months__c": null,
#     "Tier_1_Account__c": false,
#     "Total_Amount_Purchased__c": "0",
#     "Total_Cloud_ACV_Amount__c": "0",
#     "Total_Confluent_Cloud_Spend__c": null,
#     "Total_On_Prem_Spend__c": null,
#     "Total_PS_Purchased__c": "0",
#     "Total_PS_Spend__c": null,
#     "Total_Spend__c": null,
#     "Total_Subscription_Purchased__c": "0",
#     "Total_Training_Purchased__c": "0",
#     "Total_Training_Spend__c": null,
#     "Training_Balance__c": null,
#     "Type": "Prospect - Inactive",
#     "Ultimate_First_Subscription_Close_Date__c": null,
#     "Ultimate_Parent_Account_Id__c": null,
#     "Ultimate_Parent_Account_Is_Correct__c": null,
#     "Ultimate_Parent_Account_Lookup__c": null,
#     "Ultimate_Parent_Account_Name__c": null,
#     "Ultimate_Parent_Account__c": null,
#     "Uses_Our_IP__c": null,
#     "Validation_Complete__c": false,
#     "Website": "https://www.Tesla.com/",
#     "Won__c": 0.0,
#     "Years_in_Business__c": null,
#     "Zookeeper_Adoption_Date_X__c": null,
#     "Zookeeper_Adoption_Date__c": null,
#     "Zookeeper_User__c": "No",
#     "_EventType": "3B-J027yiXLMuYQdFryLLA",
#     "_ObjectType": "AccountChangeEvent",
#     "account_id_18__c": null,
#     "fferpcore__ExemptionCertificate__c": null,
#     "fferpcore__IsBillingAddressValidated__c": null,
#     "fferpcore__IsShippingAddressValidated__c": null,
#     "fferpcore__MaterializedBillingAddressValidated__c": false,
#     "fferpcore__MaterializedShippingAddressValidated__c": false,
#     "fferpcore__OutputVatCode__c": null,
#     "fferpcore__SalesTaxStatus__c": null,
#     "fferpcore__TaxCode1__c": null,
#     "fferpcore__TaxCode2__c": null,
#     "fferpcore__TaxCode3__c": null,
#     "fferpcore__TaxCountryCode__c": null,
#     "fferpcore__ValidatedBillingCity__c": null,
#     "fferpcore__ValidatedBillingCountry__c": null,
#     "fferpcore__ValidatedBillingPostalCode__c": null,
#     "fferpcore__ValidatedBillingState__c": null,
#     "fferpcore__ValidatedBillingStreet__c": null,
#     "fferpcore__ValidatedShippingCity__c": null,
#     "fferpcore__ValidatedShippingCountry__c": null,
#     "fferpcore__ValidatedShippingPostalCode__c": null,
#     "fferpcore__ValidatedShippingState__c": null,
#     "fferpcore__ValidatedShippingStreet__c": null,
#     "fferpcore__VatRegistrationNumber__c": null,
#     "fferpcore__VatStatus__c": null,
#     "iSell__OSKeyID__c": null,
#     "peopleai__FirstTouch__c": null,
#     "peopleai__LastEmailReceivedDate__c": null,
#     "peopleai__LastEmailReceivedFrom__c": null,
#     "peopleai__LastEmailSentDate__c": null,
#     "peopleai__LastEmailSentFrom__c": null,
#     "peopleai__LastMeetingDate__c": null,
#     "peopleai__LastTouch__c": null,
#     "peopleai__NextMeetingDate__c": null,
#     "peopleai__TimeSpent__c": null,
#     "peopleai__TotalTimeSpent__c": null,
#     "pse__Add_BEIs_To_Existing_Batches__c": false,
#     "pse__ERP_Worker_Correlation_Id__c": null,
#     "pse__Services_Billing_Time_Period_Type__c": null,
#     "tz__DST_Setting__c": "a7m550000000H3ZAAU",
#     "tz__LT_Info__c": null,
#     "tz__Local_Time_24_Short__c": null,
#     "tz__Local_Time_24__c": null,
#     "tz__Local_Time_Short__c": null,
#     "tz__Local_Time__c": null,
#     "tz__Timezone_DST_Full__c": "Pacific Daylight Time",
#     "tz__Timezone_DST__c": "PDT",
#     "tz__Timezone_F__c": null,
#     "tz__Timezone_Full_F__c": null,
#     "tz__Timezone_Full__c": "Pacific Standard Time",
#     "tz__Timezone_IANA__c": "America/Los_Angeles",
#     "tz__Timezone_SFDC__c": "America/Los_Angeles",
#     "tz__Timezone__c": "PST",
#     "tz__UTC_Offset_DST__c": -7.0,
#     "tz__UTC_Offset_F__c": null,
#     "tz__UTF_Offset__c": -8.0
# }


log "Verify SFDC record"
docker exec sfdx-cli sh -c "sfdx force:data:record:get  -u \"$SALESFORCE_USERNAME\" -s Account -w \"Name='Tesla'\""


# Getting Record... done
# attributes:
#   type: Account
#   url: /services/data/v53.0/sobjects/Account/0015500001NPDfSAAX
# Id: 0015500001NPDfSAAX
# IsDeleted: false
# MasterRecordId: null
# Name: Tesla
# Type: Prospect - Inactive
# RecordTypeId: 0123a0000000MuIAAU
# ParentId: null
# BillingStreet: 3500 Deer Creek Rd
# BillingCity: Palo Alto
# BillingState: California
# BillingPostalCode: 94304
# BillingCountry: United States
# BillingStateCode: CA
# BillingCountryCode: US
# BillingLatitude: null
# BillingLongitude: null
# BillingGeocodeAccuracy: null
# BillingAddress:
#   city: Palo Alto
#   country: United States
#   countryCode: US
#   geocodeAccuracy: null
#   latitude: null
#   longitude: null
#   postalCode: 94304
#   state: California
#   stateCode: CA
#   street: 3500 Deer Creek Rd
# ShippingStreet: null
# ShippingCity: null
# ShippingState: null
# ShippingPostalCode: null
# ShippingCountry: null
# ShippingStateCode: null
# ShippingCountryCode: null
# ShippingLatitude: null
# ShippingLongitude: null
# ShippingGeocodeAccuracy: null
# ShippingAddress: null
# Phone: +1 650-681-5000
# Website: https://www.tesla.com/
# PhotoUrl: null
# Industry: null
# AnnualRevenue: null
# NumberOfEmployees: null
# Description: null
# CurrencyIsoCode: USD
# OwnerId: 0053a00000L9RsbAAF
# CreatedDate: 2021-11-29T16:54:35.000+0000
# CreatedById: 0053a00000L9RsbAAF
# LastModifiedDate: 2021-11-29T16:54:36.000+0000
# LastModifiedById: 0053a00000L9RsbAAF
# SystemModstamp: 2021-11-29T16:54:36.000+0000
# LastActivityDate: null
# LastViewedDate: 2021-11-29T16:54:36.000+0000
# LastReferencedDate: 2021-11-29T16:54:36.000+0000
# JigsawCompanyId: null
# Partner_Pillar__c: null
# Geo__c: North America
# Region__c: US - California
# Account_Count__c: 1
# Nominate_for_Reference__c: false
# Publicly_Reference_able_Customer__c: false
# Partner_Classification_Tier__c: null
# Partner_Account_Status__c: null
# Executed_Confluent_Agreements__c: null
# Role_Type__c: null
# Primary_Geo_Sell__c: null
# Partner_Top_Verticals__c: null
# Subscription_End_Date_Cloud_ACV__c: null
# Partner_Interest__c: null
# Partner_Interest_Category__c: null
# Partner_Agreement__c: false
# Partner_Kafka_Connector_Interest__c: null
# Company_HQ_Country__c: null
# Years_in_Business__c: null
# Employee_Size_Tier__c: null
# Opps_Count_Rollup__c: 0
# Opps_Amount_Rollup__c: 0
# Active_Opps_Rollup__c: 0
# Won__c: 0
# Count__c: 1
# LID__LinkedIn_Company_Id__c: null
# Primary_LAX_Account_Tier__c: false
# Adoption_Phase__c: null
# New_Logo_Date__c: null
# First_Subscription_Close_Date__c: null
# LAX_Account_Tier_Report__c: null
# Partner_Prioritization_Ranking__c: null
# DSCORGPKG__Conflict__c: null
# DSCORGPKG__DO_3yr_Employees_Growth__c: null
# DSCORGPKG__DO_3yr_Sales_Growth__c: null
# DSCORGPKG__DeletedFromDiscoverOrg__c: false
# DSCORGPKG__DiscoverOrg_Created_On__c: null
# DSCORGPKG__DiscoverOrg_First_Update__c: null
# Domain__c: tesla.com/
# EBV_Rollup__c: 0
# Customer_Solution_Owner__c: null
# Procurement_Tool__c: null
# LeanData__LD_EmailDomain__c: null
# LeanData__LD_EmailDomains__c: null
# LeanData__Reporting_Customer__c: false
# LeanData__Reporting_Has_Opportunity__c: false
# LeanData__Reporting_Last_Marketing_Touch_Date__c: null
# LeanData__Reporting_Last_Sales_Touch_Date__c: null
# LeanData__Reporting_Recent_Marketing_Touches__c: null
# LeanData__Reporting_Target_Account_Number__c: 0
# LeanData__Reporting_Target_Account__c: false
# LeanData__Reporting_Total_Leads_and_Contacts__c: null
# LeanData__Reporting_Total_Marketing_Touches__c: null
# LeanData__Routing_Action__c: null
# LeanData__SLA__c: null
# LeanData__Scenario_1_Owner__c: null
# LeanData__Scenario_2_Owner__c: null
# LeanData__Scenario_3_Owner__c: null
# LeanData__Scenario_4_Owner__c: null
# LeanData__Search__c: koeajzrqlxjs w:tesla.com tesla a:3500-94304
# LeanData__Tag__c: null
# Focus_Account__c: false
# DSCORGPKG__DiscoverOrg_FullCountryName__c: null
# DSCORGPKG__DiscoverOrg_ID__c: null
# DSCORGPKG__DiscoverOrg_LastUpdate__c: null
# DSCORGPKG__DiscoverOrg_State_Full_Name__c: null
# DSCORGPKG__DiscoverOrg_Technologies__c: null
# DSCORGPKG__Exclude_Update__c: false
# DSCORGPKG__External_DiscoverOrg_Id__c: null
# DSCORGPKG__Fiscal_Year_End__c: null
# DSCORGPKG__Fortune_Rank__c: null
# DSCORGPKG__ITOrgChart__c: N/A
# DSCORGPKG__IT_Budget__c: 0
# DSCORGPKG__IT_Employees__c: null
# DSCORGPKG__Lead_Source__c: None
# DSCORGPKG__Locked_By_User__c: null
# DSCORGPKG__NAICS_Codes__c: null
# DSCORGPKG__Ownership__c: null
# DSCORGPKG__SIC_Codes__c: null
# DUNS_Number__c: null
# DUNS_Parent__c: null
# DO_Annual_Revenue__c: null
# DO_Industry__c: null
# DO_Employees__c: null
# DO_HQ_State__c: null
# DO_HQ_Country__c: null
# Account_Revenue_Band__c: null
# Global_2000_Rank__c: null
# Subscription_End_Date__c: null
# Current_Subscription_Customer__c: false
# Total_Subscription_Purchased__c: 0
# Total_Training_Purchased__c: 0
# Total_PS_Purchased__c: 0
# Total_Amount_Purchased__c: 0
# DSG_Favored_Account__c: false
# Total_Cloud_ACV_Amount__c: 0
# First_Cloud_Subscription_Date__c: null
# Renewal_Language__c: null
# RelaywareID__c: null
# Technical_Account_Manager__c: null
# Sync_To_Relayware__c: false
# Custom_Contract_Terms__c: null
# Confluent_Product_Usage__c: null
# Product_Version__c: null
# NPS__c: null
# CSAT_Support__c: null
# CSAT_Training__c: null
# CSAT_PS__c: null
# Adoption_Stage__c: null
# Maturity_Level__c: null
# Platinum_Subscription_on_Open_Renewals__c: 0
# First_Annual_Subscription_Close_Date__c: null
# Public_Clouds__c: null
# Kafka_Connect_Adoption_Date__c: null
# Private_Clouds__c: null
# Kafka_Streams_Adoption_Date__c: null
# Public_Private_Clouds__c: null
# Security_Plug_Ins_Adoption_Date__c: null
# Confluent_Proprietary_Connectors__c: null
# Last_QBR_Date__c: null
# Next_QBR_Date__c: null
# CAB_Member__c: false
# Account_Priority__c: null
# Exec_Sponsor__c: null
# Customer_Health_Overall__c: null
# Zookeeper_Adoption_Date__c: null
# Kafka_Server_Adoption_Date__c: null
# Replicator_Kafka_Connect_Adoption_Date__c: null
# Mirror_Maker_Adoption_Date__c: null
# C3_Adoption_Date__c: null
# Auto_Data_Balancer_Adoption_Date__c: null
# Rest_Proxy_Adoption_Date__c: null
# Schema_Registry_Adoption_Date__c: null
# Auto_Data_Balancer_User__c: No
# C3_User__c: No
# Kafka_Server_User__c: No
# Mirror_Maker_User__c: No
# Replicator_Kafka_Connect_User__c: No
# Rest_Proxy_User__c: No
# Schema_Registry_User__c: No
# Subscription_Tier__c: null
# Zookeeper_User__c: No
# KSQL_Adoption_Date__c: null
# PAB__c: false
# Support_Onboarding_Date__c: null
# Production_Launch_Date__c: null
# Services_Balance__c: null
# Training_Balance__c: null
# Kafka_Streams__c: No
# Security_Plug_Ins__c: No
# KSQL__c: No
# Kafka_Connect__c: No
# Kafka_Connect_Adoption_Date_X__c: null
# Kafka_Streams_Adoption_Date_X__c: null
# Security_Plug_Ins_Adoption_Date_X__c: null
# Zookeeper_Adoption_Date_X__c: null
# Mirror_Maker_Adoption_Date_X__c: null
# C3_Adoption_Date_X__c: null
# Auto_Data_Balancer_Adoption_Date_X__c: null
# Rest_Proxy_Adoption_Date_X__c: null
# Schema_Registry_Adoption_Date_X__c: null
# KSQL_Adoption_Date_X__c: null
# Replicator_Kafka_Connect_Adoption_Date_X__c: null
# Confluent_Open_Source_Connectors__c: null
# SBQQ__AssetQuantitiesCombined__c: false
# SBQQ__CoTermedContractsCombined__c: false
# SBQQ__CoTerminationEvent__c: null
# SBQQ__ContractCoTermination__c: Never
# SBQQ__DefaultOpportunity__c: null
# SBQQ__IgnoreParentContractedPrices__c: false
# SBQQ__PreserveBundle__c: true
# SBQQ__PriceHoldEnd__c: null
# SBQQ__RenewalModel__c: Contract Based
# SBQQ__RenewalPricingMethod__c: Same
# SBQQ__TaxExempt__c: No
# Opp_Renewal_Sum_Rollup__c: 0
# Product_Adoption_Implemented_Date_Time__c: null
# Product_Adoption_Filled__c: false
# Product_Adoption_Date__c: null
# Sales_Engineer_SE__c: null
# Validation_Complete__c: false
# Confluent_Cloud_User__c: No
# Confluent_Cloud_Adoption_Date__c: null
# Account_Manager__c: null
# Account_Level__c: null
# Partner_Agreement_Signed_Contact__c: null
# Region_New_Backend__c: US - California
# Domestic_Ultimate_Account__c: null
# Global_Ultimate_Account__c: null
# Dummy_Workflow_Field__c: null
# account_id_18__c: 0015500001NPDfSAAX
# DO_HQ_Street__c: null
# DO_HQ_City__c: null
# DO_HQ_Postal_Code__c: null
# Exec_Sponser_NEW__c: null
# CCP_Users__c: null
# Ultimate_First_Subscription_Close_Date__c: null
# District__c: null
# Geo_Region__c: null
# Territories__c: null
# Theatre__c: null
# Renewal_Risk_Status__c: null
# Tickets_Opened_Last_6_Months__c: null
# Tier_1_Account__c: false
# Uses_Our_IP__c: null
# EAM_Owner__c: null
# Initial_Subscription_Start_Date__c: null
# BenchMark__c: false
# Sequoia_Company__c: false
# Ticket_Opened_Last_3_Months__c: null
# Cloudy_Account_1__c: false
# Owner_Active__c: true
# Max_Subscription_End_Date_Gold__c: null
# Max_Subscription_End_Date_PLA__c: null
# IsParent__c: false
# NS_SFDC_Billing_Address_ID__c: null
# NS_SFDC_Shipping_Address_ID__c: null
# Netsuite_Currency__c: US Dollar
# Netsuite_Customer_ID__c: null
# Netsuite_Subsidiary__c: Confluent, Inc
# tz__DST_Setting__c: a7m550000000H3ZAAU
# tz__LT_Info__c: null
# tz__Local_Time_24_Short__c: 10:04 PDT
# tz__Local_Time_24__c: 11/29/2021 10:04 PDT
# tz__Local_Time_Short__c: 10:04 AM PDT
# tz__Local_Time__c: 11/29/2021 10:04 AM PDT
# tz__Timezone_DST_Full__c: Pacific Daylight Time
# tz__Timezone_DST__c: PDT
# tz__Timezone_F__c: PDT
# tz__Timezone_Full_F__c: Pacific Daylight Time
# tz__Timezone_Full__c: Pacific Standard Time
# tz__Timezone_IANA__c: America/Los_Angeles
# tz__Timezone_SFDC__c: America/Los_Angeles
# tz__Timezone__c: PST
# tz__UTC_Offset_DST__c: -7
# tz__UTC_Offset_F__c: -7
# tz__UTF_Offset__c: -8
# DNBoptimizer__DNB_D_U_N_S_Number__c: null
# DNBoptimizer__DnBCompanyRecord__c: null
# DNBoptimizer__Number_Of_Opportunity__c: 0
# Annual_Revenue_Band__c: null
# Annual_Revenue_Override__c: null
# D_B_Annual_Revenue__c: 0
# D_B_Global_Ultimate_DUNS_Number__c: null
# D_B_Number_of_Employees__c: 0
# D_B_Parent_DUNS_Number__c: null
# Employee_Size_Override__c: null
# iSell__OSKeyID__c: null
# fferpcore__ExemptionCertificate__c: null
# fferpcore__IsBillingAddressValidated__c: false
# fferpcore__IsShippingAddressValidated__c: false
# fferpcore__MaterializedBillingAddressValidated__c: false
# fferpcore__MaterializedShippingAddressValidated__c: false
# fferpcore__OutputVatCode__c: null
# fferpcore__SalesTaxStatus__c: null
# fferpcore__TaxCode1__c: null
# fferpcore__TaxCode2__c: null
# fferpcore__TaxCode3__c: null
# fferpcore__TaxCountryCode__c: null
# fferpcore__ValidatedBillingCity__c: null
# fferpcore__ValidatedBillingCountry__c: null
# fferpcore__ValidatedBillingPostalCode__c: null
# fferpcore__ValidatedBillingState__c: null
# fferpcore__ValidatedBillingStreet__c: null
# fferpcore__ValidatedShippingCity__c: null
# fferpcore__ValidatedShippingCountry__c: null
# fferpcore__ValidatedShippingPostalCode__c: null
# fferpcore__ValidatedShippingState__c: null
# fferpcore__ValidatedShippingStreet__c: null
# fferpcore__VatRegistrationNumber__c: null
# fferpcore__VatStatus__c: null
# pse__Add_BEIs_To_Existing_Batches__c: false
# pse__ERP_Worker_Correlation_Id__c: null
# pse__Services_Billing_Time_Period_Type__c: null
# Created_through_Lead_Conversion__c: false
# Exemption_from_Opp_Owner_Mismatch__c: false
# Current_MDF_Balance__c: null
# Primary_Partner_Business__c: null
# Confluent_Program_of_Interest__c: null
# Partner_Category__c: null
# Exclude_from_Account_Type_Logic__c: false
# Customer_360_Last_Updated__c: null
# Customer_Cloud_Environments__c: null
# Products_Used__c: null
# Account_Coverage_Type__c: null
# Ready_To_Sync__c: false
# New_Partner_Agreement_Signed__c: null
# Route_Leads_to_Account_Owner__c: false
# Sync_Error__c: null
# Sync_Status__c: null
# Ultimate_Parent_Account_Id__c: null
# Ultimate_Parent_Account__c: <a href="/" target="_self"> </a>
# Connectors_in_Use__c: null
# Partner_Level__c: null
# Ultimate_Parent_Account_Name__c: null
# Total_Confluent_Cloud_Spend__c: null
# Total_On_Prem_Spend__c: null
# Total_PS_Spend__c: null
# Total_Spend__c: null
# Total_Training_Spend__c: null
# Ultimate_Parent_Account_Is_Correct__c: true
# Ultimate_Parent_Account_Lookup__c: null
# Fee_Waiver__c: null
# Membership_End_Date__c: null
# Membership_Fee_Paid__c: null
# Membership_Start_Date__c: null
# Payment_Invoice__c: null
# Restricted_Account__c: false
# Federal_US_Only__c: false
# peopleai__FirstTouch__c: null
# peopleai__LastEmailReceivedDate__c: null
# peopleai__LastEmailReceivedFrom__c: null
# peopleai__LastEmailSentDate__c: null
# peopleai__LastEmailSentFrom__c: null
# peopleai__LastMeetingDate__c: null
# peopleai__LastTouch__c: null
# peopleai__NextMeetingDate__c: null
# peopleai__TimeSpent__c: null
# peopleai__TotalTimeSpent__c: null
# ARR__c: 0
# BVC_Engagement_Date__c: null
