const SHEET_NAME = "Waitlist";

function doPost(e) {
  const sheet = getSheet_();
  const data = JSON.parse(e.postData.contents || "{}");
  const row = [
    new Date(),
    data.email || "",
    data.name || "",
    data.role || "",
    data.company || "",
    data.source || "",
    data.page || "",
  ];

  sheet.appendRow(row);

  return jsonResponse_({ ok: true });
}

function doGet() {
  return jsonResponse_({ ok: true, message: "EchoPanel waitlist endpoint" });
}

function getSheet_() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = spreadsheet.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = spreadsheet.insertSheet(SHEET_NAME);
    sheet.appendRow(["timestamp", "email", "name", "role", "company", "source", "page"]);
  }
  return sheet;
}

function jsonResponse_(payload) {
  const output = ContentService.createTextOutput(JSON.stringify(payload));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}
