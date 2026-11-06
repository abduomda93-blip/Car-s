function doPost(e) {
  try {
    var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
    var data = JSON.parse(e.postData.contents);
    
    // إنشاء رأس الجدول تلقائياً إذا كان الشيت جديداً وفارغاً
    if (sheet.getLastRow() === 0) {
      sheet.appendRow([
        "معرف الرحلة", 
        "تاريخ التسجيل", 
        "تاريخ الرحلة", 
        "رقم اللوحة", 
        "موديل السيارة", 
        "اسم السائق", 
        "عداد الخروج (كم)", 
        "عداد الرجوع (كم)", 
        "المسافة المقطوعة (كم)", 
        "وقت الخروج", 
        "وقت الرجوع", 
        "ملاحظات"
      ]);
      
      // تنسيق السطر الأول بلون أنيق
      var headerRange = sheet.getRange(1, 1, 1, 12);
      headerRange.setFontWeight("bold");
      headerRange.setBackground("#0d9488");
      headerRange.setFontColor("#ffffff");
    }
    
    sheet.appendRow([
      data.id || "",
      new Date().toLocaleString("ar-SA"),
      data.date || "",
      data.plateNumber || "",
      data.carModel || "",
      data.driverName || "",
      data.startMeter !== undefined ? data.startMeter : "",
      data.endMeter !== undefined ? data.endMeter : "",
      data.distance !== undefined ? data.distance : "",
      data.startTime || "",
      data.endTime || "",
      data.notes || ""
    ]);
    
    return ContentService.createTextOutput(JSON.stringify({ "status": "success", "message": "Trip recorded successfully" }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({ "status": "error", "message": error.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
