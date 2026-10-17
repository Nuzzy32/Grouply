import XCTest

final class GrouplyUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--uitesting"]
    app.launch()
  }

  @MainActor
  func testFourTabsAndReviewApproval() throws {
    login("u1")
    XCTAssertTrue(app.buttons["open-profile"].waitForExistence(timeout: 5))
    screenshot("01-Beranda")
    app.buttons["tab-1"].tap()
    XCTAssertTrue(app.staticTexts["Basis Data · Kelompok 3"].waitForExistence(timeout: 5))
    screenshot("02-Grup")
    app.buttons["tab-2"].tap()
    XCTAssertTrue(
      app.staticTexts["Satu ruang obrolan untuk tiap grup"].waitForExistence(timeout: 5))
    screenshot("03-Chat")
    app.buttons["tab-3"].tap()
    XCTAssertTrue(
      app.staticTexts["4 terbuka · 1 menunggu review kamu"].waitForExistence(timeout: 5))
    screenshot("04-Tugas-Saya")
    app.buttons["tab-0"].tap()
    let erd = app.staticTexts["Draft diagram ERD"].firstMatch
    reveal(erd)
    erd.tap()
    XCTAssertTrue(app.buttons["open-review"].waitForExistence(timeout: 5))
    screenshot("05-Detail-Tugas")
    app.buttons["open-review"].tap()
    XCTAssertTrue(app.buttons["approve-work"].waitForExistence(timeout: 5))
    screenshot("06-Review")
    app.buttons["approve-work"].tap()
    XCTAssertTrue(app.staticTexts["Disetujui"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testAssigneeStartsAndSubmitsTask() throws {
    login("u2")
    app.buttons["tab-3"].tap()
    let task = app.staticTexts["Kamus data"].firstMatch
    reveal(task)
    task.tap()
    let start = app.buttons["Mulai Kerjakan"]
    reveal(start)
    start.tap()
    let submit = app.buttons["Kirim Hasil"]
    XCTAssertTrue(submit.waitForExistence(timeout: 5))
    submit.tap()
    let note = app.textFields["submission-note"]
    XCTAssertTrue(note.waitForExistence(timeout: 5))
    note.tap()
    note.typeText("Kamus data lengkap dengan tipe atribut dan contoh nilai.")
    app.buttons["submit-work"].tap()
    XCTAssertTrue(app.staticTexts["Menunggu review"].firstMatch.waitForExistence(timeout: 5))
    screenshot("07-Hasil-Terkirim")
  }

  @MainActor
  func testGroupChatSend() throws {
    login("u4")
    app.buttons["tab-2"].tap()
    app.staticTexts["Basis Data · Kelompok 3"].firstMatch.tap()
    let field = app.textFields["Tulis pesan…"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("Siap, kita lanjut diskusinya di sini.")
    app.buttons["Kirim pesan"].tap()
    XCTAssertTrue(
      app.staticTexts["Siap, kita lanjut diskusinya di sini."].waitForExistence(timeout: 5))
    screenshot("08-Pesan-Grup")
  }

  @MainActor
  func testCreateGroupAndProjectOpensTheirDetails() throws {
    login("u1")
    app.buttons["tab-1"].tap()
    app.buttons["group-create"].tap()
    let name = app.textFields["group-name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Tim Demo Native")
    app.buttons["group-save"].tap()
    XCTAssertTrue(app.buttons["create-project"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Tim Demo Native"].waitForExistence(timeout: 5))
    app.buttons["create-project"].tap()
    let title = app.textFields["project-title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("Proyek Perdana")
    app.buttons["project-save"].tap()
    XCTAssertTrue(app.buttons["add-task"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Proyek Perdana"].waitForExistence(timeout: 5))
    screenshot("10-Proyek-Baru")
  }

  @MainActor
  func testLargeTextLayout() throws {
    app.terminate()
    app.launchArguments += [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    login("u1")
    XCTAssertTrue(app.buttons["tab-3"].isHittable)
    app.buttons["tab-3"].tap()
    XCTAssertTrue(app.staticTexts["Tugas Saya"].firstMatch.waitForExistence(timeout: 5))
    screenshot("09-Dynamic-Type")
  }

  @MainActor
  private func login(_ persona: String) {
    let button = app.buttons["persona-\(persona)"]
    reveal(button)
    button.tap()
  }

  @MainActor
  private func reveal(_ element: XCUIElement) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.exists && element.isHittable, "Expected visible element: \(element)")
  }

  @MainActor
  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
