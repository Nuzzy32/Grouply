import XCTest

final class BackendUITests: XCTestCase {
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
