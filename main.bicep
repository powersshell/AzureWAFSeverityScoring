param logAnalyticsWorkspaceName string
param dataCollectionEndpointName string
param dataCollectionRuleName string
param customTableName string
param location string = resourceGroup().location

var updatedCustomTableName = 'Custom-${customTableName}_CL'
param scheduledRunbookTime string = utcNow('u')

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: dataCollectionEndpointName
  location: location
  properties: {
    
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  location: location
  name: dataCollectionRuleName
  properties: {
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: logAnalyticsWorkspace.properties.customerId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          '${updatedCustomTableName}'
        ]
        destinations:  [
          logAnalyticsWorkspace.properties.customerId
        ]
        transformKql: 'source | extend TimeGenerated = now()'
        outputStream: updatedCustomTableName
      }
    ]
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      '${updatedCustomTableName}': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'ruleId'
            type: 'string'
          }
          {
            name: 'ruleSeverity'
            type: 'string'
          }
          {
            name: 'ruleScore'
            type: 'int'
          }
        ]
      }
    }
  }
}

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: '${customTableName}_CL'
  properties: {
    plan: 'Analytics'
    totalRetentionInDays: 30
    retentionInDays: 30
    schema: {
      name: '${customTableName}_CL'
      columns: [
        {
          name: 'TimeGenerated'
          type: 'datetime'
        }
        {
          name: 'ruleId'
          type: 'string'
        }
        {
          name: 'ruleSeverity'
          type: 'string'
        }
        {
          name: 'ruleScore'
          type: 'int'
        }
      ]
    }

  }
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: 'automationaccount'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  location: location
  name: 'GetWAFSeverityScores'
  properties: {
    runbookType: 'PowerShell72'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/powersshell/AzureWAFSeverityScoring/main/Get-WAFSeverities.ps1'
    }
    
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.name, resourceGroup().id, '3913510d-42f4-4e42-8a64-420c390055eb')
  properties: {
    principalId: automationAccount.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
    principalType: 'ServicePrincipal'
  }
  scope: dataCollectionRule
}

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'GetWAFSeverityScores'
  properties: {
    startTime: dateTimeAdd(scheduledRunbookTime, 'PT15M')
    frequency: 'Month'
    interval: 1
    expiryTime: dateTimeAdd(scheduledRunbookTime, 'P10Y')
   }

}

resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.name, runbook.name, schedule.name)
  properties: {
    runbook: {
      name: runbook.name
    }
    schedule: {
      name: schedule.name
    }
    parameters: {
          DCRImmutableID: dataCollectionRule.properties.immutableId
          DataCollectionEndpointURI: dataCollectionEndpoint.properties.logsIngestion.endpoint
          tableName: '${customTableName}_CL'
    }
  }
}

output dataCollectionRuleImmutableId string = dataCollectionRule.properties.immutableId
output dataCollectionEndpoint string = dataCollectionEndpoint.properties.logsIngestion.endpoint
output cutomTableName string = '${customTableName}_CL'
