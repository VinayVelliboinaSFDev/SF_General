public class LecturerSalaryHandler {
    public static void updateLecturerSalary(List<Contact> contacts) {
        // Get Lecturer RecordTypeId
        Id lecturerRecordTypeId;
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        
        for (RecordType rt : [SELECT Id, Name FROM RecordType WHERE SObjectType = 'Contact']) {
            recordTypeMap.put(rt.Name, rt.Id);
        }
        
        lecturerRecordTypeId = recordTypeMap.get('Lecturer');

        for (Contact con : contacts) {
            if (con.RecordTypeId == lecturerRecordTypeId && con.Years_of_Experience__c != null) {
                Integer experience = con.Years_of_Experience__c.intValue();
                
                if (experience < 1) {
                    con.Monthly_Salary__c = 22000;
                } else if (experience >= 2 && experience <= 3) {
                    con.Monthly_Salary__c = 28000;
                } else if (experience >= 4 && experience <= 6) {
                    con.Monthly_Salary__c = 35000;
                } else if (experience > 6) {
                    con.Monthly_Salary__c = 45000;
                }
            }
        }
    }
    
    public static void assignEmployeeID(List<Contact> contacts) {
        Set<String> existingIds = new Set<String>();

        // Query existing Employee IDs
        for (Contact con : [SELECT Employee_ID__c FROM Contact WHERE Employee_ID__c != NULL]) {
            existingIds.add(con.Employee_ID__c);
        }

        Integer startIndex = [SELECT COUNT() FROM Contact] + 1; // Ensures sequential unique IDs

        for (Contact con : contacts) {
            if (con.Employee_ID__c == null) { // Generate only if not set
                String newId;

                while (true) {
                    newId = 'EMP-' + String.valueOf(startIndex);
                    if (!existingIds.contains(newId)) {
                        con.Employee_ID__c = newId;
                        existingIds.add(newId);
                        startIndex++;
                        break;
                    }
                }
            }
        }
    }
}