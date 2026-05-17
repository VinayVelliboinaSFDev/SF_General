trigger LecturerSalaryTrigger on Contact (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            LecturerSalaryHandler.updateLecturerSalary(Trigger.new);
        }
        if (Trigger.isInsert) {
            LecturerSalaryHandler.assignEmployeeID(Trigger.new);
        }
    }
}