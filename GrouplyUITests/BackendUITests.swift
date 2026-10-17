import XCTest

final class BackendUITests: XCTestCase {
  @MainActor func testDeletionExplainsPrerequisitesWithoutAutomaticReassignment() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitesting"]
    app.launch()
    let persona = app.buttons["persona-u1"]
    for _ in 0..<6 {
      if persona.exists && persona.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(persona.exists && persona.isHittable)
    persona.tap()
    let profile = app.buttons["open-profile"]
    XCTAssertTrue(profile.waitForExistence(timeout: 5))
    profile.tap()
    let delete = app.buttons["delete-account"]
    for _ in 0..<6 {
      if delete.exists && delete.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(delete.exists && delete.isHittable)
    delete.tap()
    XCTAssertTrue(app.staticTexts["Ini simulasi penghapusan akun demo, bukan akun server."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Tidak ada pengalihan otomatis.")).firstMatch.exists)
    let next = app.buttons["Lanjutkan"]
    for _ in 0..<4 {
      if next.exists && next.isHittable { break }
      app.swipeUp()
    }
    next.tap()
    XCTAssertTrue(app.staticTexts["Serahkan peran koordinator dulu sebelum menghapus akun."].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["confirm-delete-account"].exists)
  }

  @MainActor func testBackendLoginRequiresCredentialsWithoutSubmittingSecrets() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--uitesting"]
    app.launch()
    let open = app.buttons["open-backend-login"]
    for _ in 0..<6 {
      if open.exists && open.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(open.exists && open.isHittable)
    open.tap()
    XCTAssertTrue(app.navigationBars["Masuk Akun"].waitForExistence(timeout: 5))
    let email = app.textFields["backend-email"]
    guard email.waitForExistence(timeout: 3) else {
      XCTAssertTrue(
        app.staticTexts[
          "Konfigurasi server belum tersedia. Ikuti docs/BACKEND_SETUP.md, lalu build ulang aplikasinya."
        ].exists)
      return
    }
    XCTAssertTrue(app.secureTextFields["backend-password"].exists)
    let signIn = app.buttons["backend-signin"]
    for _ in 0..<5 {
      if signIn.exists && signIn.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(signIn.exists)
    XCTAssertFalse(signIn.isEnabled)
    XCTAssertFalse(app.staticTexts["backend-login-error"].exists)
    app.buttons["Batal"].tap()
    XCTAssertTrue(open.waitForExistence(timeout: 5))
  }
}
