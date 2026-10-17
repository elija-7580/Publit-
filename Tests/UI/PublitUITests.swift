import CoreLocation
import XCTest

/// End-to-end flows against the live Transitous API. Each test saves a screenshot
/// (`$SIMULATOR_HOST_HOME/publit-shots/<name>.png` on CI) for the README and website.
final class PublitUITests: XCTestCase {
    private let timeout: TimeInterval = 45

    /// Started per test. CI has one 45-minute job for build and all UI tests; a single hanging
    /// test must not use it up, or no log at all is published. After this many seconds the runner
    /// stops, xcodebuild reports the test as crashed and continues with the next one.
    private static let watchdogSeconds: TimeInterval = 150
    private var watchdog: DispatchWorkItem?
    private var startedAt = Date()

    override func setUp() {
        continueAfterFailure = false
        startedAt = Date()
        let name = self.name
        let item = DispatchWorkItem {
            print("WATCHDOG: \(name) still running after \(Int(Self.watchdogSeconds)) s - stopping the runner")
            fflush(stdout)
            abort()
        }
        watchdog = item
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.watchdogSeconds, execute: item)
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
    }

    /// Repeats each failure on its own line as a GitHub Actions annotation, so failing UI tests are
    /// visible on pull requests (which do not publish to the ci-results branch). xcodebuild prints
    /// the failure message as is, the runner's own stdout does not reach the job log.
    override func record(_ issue: XCTIssue) {
        var issue = issue
        let line = issue.sourceCodeContext.location?.lineNumber ?? 0
        let text = issue.compactDescription.replacingOccurrences(of: "\n", with: " ")
        issue.compactDescription = text + "\n::error file=Tests/UI/PublitUITests.swift,line=\(line)::\(name) \(text) (error: UI test)"
        super.record(issue)
    }

    override func tearDown() {
        watchdog?.cancel()
        // The screen at the moment of failure, published with the CI screenshots.
        if testRun?.hasSucceeded == false {
            let test = name.split(separator: " ").last.map { String($0.dropLast()) } ?? "test"
            snap("failed-\(test)")
        }
        print("TIMING: \(name) \(Int(Date().timeIntervalSince(startedAt))) s")
    }

    private func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = env
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Touch the top edge (no controls there) so a pending permission alert is handled,
    /// without tapping into the list like `app.tap()` (screen centre) does.
    private func nudge(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
    }

    /// Waits for an element in a lazy list, scrolling down when it is not there yet.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.waitForExistence(timeout: 4) {
                // Short drags: a full swipe can scroll a row past the top in one go.
                let window = app.windows.firstMatch
                for _ in 0..<10 where !element.isHittable {
                    let up = element.frame.minY > window.frame.midY
                    let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.35))
                    let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.6))
                    from.press(forDuration: 0.05, thenDragTo: to)
                }
                return element.isHittable
            }
            app.swipeUp()
        }
        return element.exists
    }

    /// Scrolls until the element sits in the upper part of the list, clear of the tab bar and the
    /// live trip bar above it (a tap there would open the trip). Drags start high on the screen:
    /// maps sit lower in the list and would pan instead of scrolling it.
    private func bringUp(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var drags = 0
        while Date() < deadline, drags < 16 {
            let height = window.frame.height
            var down = false
            if element.waitForExistence(timeout: 2) {
                let frame = element.frame
                if frame.minY > height * 0.12, frame.maxY < height * 0.7 { return element.isHittable }
                down = frame.maxY < height * 0.7
            }
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.2 : 0.32))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.42 : 0.1))
            from.press(forDuration: 0.05, thenDragTo: to)
            drags += 1
        }
        return element.exists && element.isHittable
    }

    /// Taps the element's centre even when XCUITest reports a Menu in a list row as not hittable.
    private func tapCentre(_ element: XCUIElement) {
        if element.isHittable { element.tap() } else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            let dir = URL(fileURLWithPath: home).appendingPathComponent("publit-shots")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    /// F08 German localization: navigation, route planning and long Settings footers.
    func testF08GermanLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launchEnvironment = ["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Planen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Von")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Nach")).firstMatch.exists)
        sleep(3)
        snap("de-plan")
        app.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Öffentlicher Verkehr ohne Ablenkung.")).firstMatch.exists)
        snap("de-settings")
        app.buttons["Fertig"].tap()
        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["In der Nähe"].waitForExistence(timeout: 5))
        snap("de-nearby")
        app.tabBars.buttons["Gespeichert"].tap()
        XCTAssertTrue(app.navigationBars["Gespeichert"].waitForExistence(timeout: 5))
        snap("de-saved")
    }

    private func sample(_ kind: String, dark: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
        app.launchEnvironment = ["PUBLIT_UI_SAMPLE": kind, "PUBLIT_UI_DARK": dark ? "1" : "0", "PUBLIT_UI_LARGE": large ? "1" : "0"]
        app.launch()
        return app
    }

    func testF09TransitPresentationLightDarkAndAccessibility() {
        for (name, dark, large) in [("board-light", false, false), ("board-dark", true, false), ("board-large", false, true)] {
            let app = sample("board", dark: dark, large: large)
            XCTAssertTrue(app.navigationBars["Abfahrten"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.otherElements["departureRow"].firstMatch.exists || app.cells.firstMatch.exists)
            snap(name)
            if !large { app.swipeUp(); snap(name + "-edge-cases") }
            app.terminate()
        }
        let app = sample("leg")
        XCTAssertTrue(app.staticTexts["Einsteigen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Aussteigen"].exists)
        XCTAssertTrue(app.staticTexts["Nordfriedhof"].exists)
        snap("direction-versus-alighting")
        app.terminate()
        let widgets = sample("widget")
        XCTAssertTrue(widgets.navigationBars["Fahrt"].waitForExistence(timeout: 5))
        snap("widget-small-medium")
        widgets.terminate()
    }

    /// F21 Design screenshots of the real trip screens on a longer sample trip, light and dark:
    /// the route preview, the live trip with the panel down and pulled up.
    func testF21DesignScreens() {
        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            var app = sample("route", dark: dark)
            allowLocation()
            sleep(6) // map tiles
            snap("design-route\(suffix)")
            app.swipeUp()
            sleep(1)
            snap("design-route-steps\(suffix)")
            app.terminate()

            app = sample("live", dark: dark)
            allowLocation()
            sleep(10) // map tiles
            snap("design-live\(suffix)")
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
            sleep(2)
            snap("design-live-up\(suffix)")
            app.swipeUp()
            sleep(1)
            snap("design-live-up-more\(suffix)")
            app.terminate()
        }
    }

    /// The start screens (Nearby, Plan with results, Tickets, Saved), light and dark.
    func testF22StartScreens() {
        for dark in [false, true] {
            let suffix = dark ? "-dark" : ""
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_AT"]
            app.launchEnvironment = ["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "nearby", "PUBLIT_UI_DARK": dark ? "1" : "0"]
            app.launch()
            allowLocation()
            sleep(10) // departures and map
            snap("start-nearby\(suffix)")
            app.swipeUp()
            sleep(2)
            snap("start-nearby-more\(suffix)")
            let tabs = app.tabBars.buttons
            tabs.element(boundBy: 1).tap()
            sleep(12) // routes
            snap("start-plan\(suffix)")
            app.swipeUp()
            sleep(2)
            snap("start-plan-more\(suffix)")
            tabs.element(boundBy: 2).tap()
            sleep(2)
            snap("start-tickets\(suffix)")
            tabs.element(boundBy: 3).tap()
            sleep(2)
            snap("start-saved\(suffix)")
            app.terminate()
        }
    }

    /// Answers the location prompt, which would cover the screenshot.
    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Beim Verwenden der App erlauben"] {
            let allow = springboard.buttons[label]
            if allow.waitForExistence(timeout: 3) { allow.tap(); return }
        }
    }

    func testF10StartEndTripAndEmbeddedTicket() {
        let app = sample("workflow")
        let start = app.buttons["startTrip"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        snap("workflow-start")
        start.tap()
        XCTAssertTrue(app.navigationBars["Aktive Fahrt"].waitForExistence(timeout: 10))
        snap("workflow-live-open")
        let activeList = app.collectionViews["activeTripList"]
        let end = activeList.buttons["endTrip"]
        for _ in 0..<6 where !end.isHittable {
            if activeList.exists { activeList.swipeUp() } else { app.swipeUp() }
        }
        snap("workflow-live")
        if !end.isHittable { print("ACTIVE TRIP HIERARCHY: \(app.debugDescription)") }
        XCTAssertTrue(end.isHittable)
        end.tap()
        XCTAssertTrue(app.buttons["startTrip"].waitForExistence(timeout: 5))
        // The ticket part of this flow returns with Features.tickets.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ticket-Beispiel")).firstMatch.exists)
    }

    func testF11DisruptionDetailsAndConditionalFareEstimate() {
        var app = sample("alerts")
        let alert = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Demo: U3")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Testmeldung")).firstMatch.waitForExistence(timeout: 5))
        snap("disruption-details")
        app.terminate()
        app = sample("fare")
        XCTAssertTrue(app.staticTexts["Preisschätzung"].waitForExistence(timeout: 5))
        snap("fare-conditional-demo")
        app.terminate()
    }

    /// F12 Ticket passes (built, not in the app yet): list, pass with code, full-screen code,
    /// check screen after recognition, import sources, dark mode and large type.
    func testF12TicketPassScreens() {
        var app = sample("passes")
        let card = app.buttons["passCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        snap("pass-wallet")
        card.tap()
        XCTAssertTrue(app.buttons["passCode"].waitForExistence(timeout: 5))
        app.terminate()

        app = sample("pass")
        let code = app.buttons["passCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        snap("pass-detail")
        code.tap()
        XCTAssertTrue(app.buttons["closeCode"].waitForExistence(timeout: 5))
        snap("pass-code")
        app.buttons["closeCode"].tap()
        app.terminate()

        app = sample("pass-editor")
        XCTAssertTrue(app.buttons["savePass"].waitForExistence(timeout: 10))
        snap("pass-editor")
        app.swipeUp()
        snap("pass-editor-look")
        app.terminate()

        app = sample("pass-import")
        XCTAssertTrue(app.buttons["importFile"].waitForExistence(timeout: 10))
        snap("pass-import")
        app.terminate()

        app = sample("passes", dark: true)
        XCTAssertTrue(app.buttons["passCard"].firstMatch.waitForExistence(timeout: 10))
        snap("pass-wallet-dark")
        app.terminate()

        app = sample("pass", large: true)
        XCTAssertTrue(app.buttons["passCode"].waitForExistence(timeout: 10))
        snap("pass-detail-large")
        app.terminate()
    }

    /// F01 Nearby: live departures around the (simulated) location.
    func testF01NearbyShowsDepartures() {
        let app = launch()
        nudge(app) // lets the interruption monitor handle a permission alert
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 10))
        // The board shows first (the link under it sits below the fold since the mode chips came).
        XCTAssertTrue(app.buttons["modeChip-all"].waitForExistence(timeout: timeout), "no departure board loaded")
        sleep(1)
        snap("nearby")

        let all = app.buttons["All departures"].firstMatch
        XCTAssertTrue(reveal(all, in: app), "no link to all departures")
        all.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        snap("stop")
        app.buttons["Save"].tap()
        app.tabBars.buttons["Saved"].tap()
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Marienplatz'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "saved stop not listed")
    }

    /// F02 Plan and compare: routes on one timeline, map overlay, route detail.
    func testF02PlanCompareAndDetail() {
        let app = launch(["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"])
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10))
        let routes = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] ' from '"))
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout), "no routes found")
        sleep(1)
        snap("plan")

        // By identifier: the label alone no longer matches once the control has an identifier.
        let mapToggle = app.descendants(matching: .any)["routeMapToggle"].firstMatch
        XCTAssertTrue(mapToggle.waitForExistence(timeout: 10), "no map toggle")
        tapCentre(mapToggle)
        // The link sits under the 320 pt map, below the fold since the first-stop picker was added.
        let details = app.buttons["Details of selected route"].firstMatch
        XCTAssertTrue(bringUp(details, in: app), "no route details link under the map")
        sleep(3) // map tiles
        snap("compare")

        details.tap()
        XCTAssertTrue(app.navigationBars["Route"].waitForExistence(timeout: 10))
        sleep(3)
        snap("detail")
        // In the steps, below the trip actions.
        XCTAssertTrue(bringUp(app.buttons["Remind me to get off"].firstMatch, in: app), "no get-off reminder in the steps")
    }

    /// F03 Search and Home: find a stop, set it as Home, plan there with one tap.
    func testF03SetHomeAndPlan() {
        let app = launch(["PUBLIT_TAB": "saved"])
        XCTAssertTrue(app.buttons["Set Home"].waitForExistence(timeout: 10))
        app.buttons["Set Home"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Sendlinger Tor")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sendlinger Tor'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: timeout), "no geocoding result")
        snap("search")
        hit.tap()
        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 5))
        snap("saved")

        // Plan has no quick destinations since build 14: Home comes first when picking a place.
        app.tabBars.buttons["Plan"].tap()
        let to = app.buttons["endpoint-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10), "no To field in Plan")
        to.tap()
        let home = app.buttons["pick-home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5), "Home missing when picking a destination")
        home.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "value == 'Sendlinger Tor'")).firstMatch.waitForExistence(timeout: 5),
                      "Home not taken as the destination")
    }

    /// F04 Edge: empty and nonsense search input must not crash and must say so.
    func testF04SearchEdgeCases() {
        let app = launch(["PUBLIT_TAB": "saved"])
        app.navigationBars["Saved"].buttons["Add"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("x")
        XCTAssertFalse(app.staticTexts["No matches."].waitForExistence(timeout: 2), "searched with 1 character")
        field.typeText("qzqzqzqzqzqz😀ä")
        XCTAssertTrue(app.staticTexts["No matches."].waitForExistence(timeout: timeout))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
    }

    /// F05 Nearby "Where to now?": routes from the current location, leaving now.
    func testF05GoNowFromNearby() {
        let app = launch()
        nudge(app)
        let whereTo = app.buttons["whereToNow"]
        XCTAssertTrue(whereTo.waitForExistence(timeout: 10))
        whereTo.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Sendlinger Tor")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sendlinger Tor'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: timeout))
        hit.tap()
        let leave = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Leave' OR label == 'Walk all the way'")).firstMatch
        XCTAssertTrue(leave.waitForExistence(timeout: timeout), "no routes from here")
        sleep(2)
        snap("gonow")
    }

    /// F06 Station map opens and shows stations around the location.
    func testF06StationMap() {
        let app = launch()
        nudge(app)
        let mapButton = app.buttons["Station map"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 10))
        mapButton.tap()
        XCTAssertTrue(app.navigationBars["Stations"].waitForExistence(timeout: 10))
        sleep(6) // tiles and stops
        snap("stationmap")
    }

    /// F07 Save a planned route: it appears under Upcoming trips in Saved, with ticket links in the details.
    func testF07SaveTripAndTickets() {
        let app = launch(["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"])
        let routes = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] ' from '"))
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout), "no routes found")
        routes.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Route"].waitForExistence(timeout: 10))
        let save = app.buttons["Save trip"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.exists, "Save trip missing")
        save.tap()
        XCTAssertTrue(app.collectionViews.buttons["Saved"].waitForExistence(timeout: 5))
        snap("tripactions")
        // Tickets for the trip: the add flow opens with the trip attached.
        // Saving shows the live trip bar over the lower screen: bring the row above it.
        let addTicket = app.buttons["addTripTicket"]
        XCTAssertTrue(bringUp(addTicket, in: app), "no ticket section on the route")
        addTicket.tap()
        XCTAssertTrue(app.buttons["importFile"].waitForExistence(timeout: 5), "add ticket did not open")
        snap("trip-add-ticket")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)
        app.navigationBars["Route"].buttons.firstMatch.tap()
        app.buttons["Clear destination"].tap()
        // Saved trips are listed in the Saved tab (Plan is for planning only).
        app.tabBars.buttons["Saved"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Flughafen München'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "saved trip not under Upcoming in Saved")
        snap("trips")
    }

    /// F13 Filters: mode chips on Nearby, lines at a station, route options and the walk/bike/car comparison.
    func testF13ModeFiltersLinesAndComparison() {
        let app = launch()
        nudge(app)
        // Earlier tests pin places and save a trip, so the first board can sit below the fold;
        // the chips at the top appear as soon as a board with several modes has loaded.
        if !app.buttons["modeChip-all"].waitForExistence(timeout: timeout) { snap("nearby-filter-fail") }
        XCTAssertTrue(app.buttons["modeChip-all"].exists, "no mode chips on Nearby")
        let chip = ["modeChip-subway", "modeChip-suburban", "modeChip-tram", "modeChip-bus"].map { app.buttons[$0] }.first { $0.exists }
        XCTAssertNotNil(chip, "no mode chips on Nearby")
        chip?.tap()
        XCTAssertTrue(reveal(app.buttons["All departures"].firstMatch, in: app), "filtered board empty")
        for _ in 0..<2 { app.swipeDown() } // back to the top for the screenshot
        sleep(2)
        snap("nearby-filter")
        app.buttons["modeChip-all"].tap()

        let all = app.buttons["All departures"].firstMatch
        XCTAssertTrue(reveal(all, in: app), "no departure board loaded")
        all.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Lines"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lineAtStop"].firstMatch.waitForExistence(timeout: timeout), "no lines at the station")
        sleep(1)
        snap("stop-lines")
        app.terminate()

        let plan = launch(["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"])
        let routes = plan.buttons.matching(NSPredicate(format: "label CONTAINS[c] ' from '"))
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout), "no routes found")
        // Driving comes a little after the routes (its own, slower request).
        let car = plan.buttons["compare-CAR"]
        let until = Date().addingTimeInterval(timeout)
        while Date() < until, !(car.waitForExistence(timeout: 2) && car.isHittable) { plan.swipeUp() }
        XCTAssertTrue(car.exists, "no driving comparison")
        sleep(1)
        snap("plan-compare")
        for _ in 0..<6 where !plan.buttons["routeOptions"].isHittable { plan.swipeDown() }
        plan.buttons["routeOptions"].tap()
        XCTAssertTrue(plan.navigationBars["Route options"].waitForExistence(timeout: 5))
        let bus = plan.switches["routeMode-bus"]
        XCTAssertTrue(bus.waitForExistence(timeout: 5))
        bus.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        sleep(1)
        snap("route-options")
        plan.buttons["routeOptionsDone"].tap()
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout), "no routes without buses")
        XCTAssertTrue(plan.buttons["routeOptions"].label.contains("Without Bus"), "filter summary missing")
        // Leave the defaults for the next run.
        plan.buttons["routeOptions"].tap()
        XCTAssertTrue(plan.navigationBars["Route options"].waitForExistence(timeout: 5))
        plan.buttons["Reset"].tap()
        plan.buttons["routeOptionsDone"].tap()
    }

    /// F14 Lines tab: lines around you, a line's route with vehicles and a stop timetable;
    /// the station map with line shapes and live vehicles; sorting routes.
    func testF14LinesTabAndLiveMap() {
        // Demo location so Lines has nearby data even when the simulator GPS is cold.
        let app = launch(["PUBLIT_DEMO": "munich"])
        nudge(app)
        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.buttons["findLine"].waitForExistence(timeout: 10))
        app.buttons["findLine"].tap()
        XCTAssertTrue(app.navigationBars["Lines"].waitForExistence(timeout: 10))
        let row = app.buttons["lineRow"].firstMatch
        if !row.waitForExistence(timeout: timeout) { snap("lines-fail") }
        XCTAssertTrue(row.exists, "no lines nearby")
        sleep(1)
        snap("lines")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lineDirection"].firstMatch.waitForExistence(timeout: timeout)
                      || app.descendants(matching: .any)["lineStop"].firstMatch.waitForExistence(timeout: 5), "line detail empty")
        sleep(5) // route shape and vehicles
        snap("line-detail")
        let stop = app.buttons["lineStop"].firstMatch
        if reveal(stop, in: app) {
            stop.tap()
            XCTAssertTrue(app.descendants(matching: .any)["lineTimetable"].firstMatch.waitForExistence(timeout: timeout), "no timetable")
            sleep(1)
            snap("line-timetable")
        }
        app.terminate()

        let map = launch()
        nudge(map)
        let mapButton = map.buttons["Station map"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 10))
        mapButton.tap()
        XCTAssertTrue(map.navigationBars["Stations"].waitForExistence(timeout: 10))
        sleep(12) // tiles, line shapes and the first vehicle positions
        snap("map-lines")
        map.terminate()

        let plan = launch(["PUBLIT_DEMO": "munich", "PUBLIT_TAB": "plan"])
        let routes = plan.buttons.matching(NSPredicate(format: "label CONTAINS[c] ' from '"))
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout), "no routes found")
        // Any element type: a SwiftUI Menu in a list row is not always reported as a button.
        let sort = plan.descendants(matching: .any)["routeSortMenu"].firstMatch
        if !reveal(sort, in: plan) { print("SORT MENU: \(sort.exists ? sort.debugDescription : "missing")") }
        XCTAssertTrue(sort.exists, "no sort menu")
        tapCentre(sort)
        let fastest = plan.buttons["Fastest"].firstMatch
        XCTAssertTrue(fastest.waitForExistence(timeout: 5))
        fastest.tap()
        XCTAssertTrue(routes.firstMatch.waitForExistence(timeout: timeout))
        sleep(1)
        snap("plan-sorted")
        // Back to the default order for the next run (not part of the check: the menu may still be closing).
        sleep(1)
        if sort.exists {
            tapCentre(sort)
            if plan.buttons["Departure"].firstMatch.waitForExistence(timeout: 5) { plan.buttons["Departure"].firstMatch.tap() }
        }
    }

    /// F15 Tickets tab: empty state, the add sheet and the way back; the stop screen's labelled actions.
    func testF15TicketsTabAndStopActions() {
        let app = launch(["PUBLIT_TAB": "tickets"])
        nudge(app)
        XCTAssertTrue(app.navigationBars["Tickets"].waitForExistence(timeout: 10), "no Tickets tab")
        let add = app.buttons["addPass"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        snap("tickets-tab")
        add.tap()
        XCTAssertTrue(app.buttons["importFile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["importPhoto"].exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))

        app.tabBars.buttons["Nearby"].tap()
        let all = app.buttons["All departures"].firstMatch
        XCTAssertTrue(reveal(all, in: app), "no link to all departures")
        all.tap()
        XCTAssertTrue(app.buttons["routeHere"].waitForExistence(timeout: 10), "no labelled Route here action")
        XCTAssertTrue(app.buttons["routeFromHere"].exists, "no labelled Route from here action")
        sleep(2) // walking time
        snap("stop-actions")
    }
    /// F16 Real file handoff always requires explicit review before the source is stored.
    func testF16SharedTicketImport() {
        for kind in ["pdf", "image", "unique"] {
            let app = launch(["PUBLIT_IMPORT_SAMPLE": kind])
            let save = app.buttons["savePass"]
            let review = save.waitForExistence(timeout: 30)
            if kind == "image", !review {
                // Some simulator hosts cannot create a Vision inference context.
                let failed = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Try another")).firstMatch
                XCTAssertTrue(failed.waitForExistence(timeout: 3), "image OCR must fail gracefully")
                snap("shared-ticket-image-fallback")
                app.terminate()
                continue
            }
            XCTAssertTrue(review, "shared file must be reviewed: \(kind)")
            XCTAssertFalse(app.staticTexts["sharedTicketAdded"].exists, "must not auto-save")
            XCTAssertTrue(bringUp(app.buttons["mapTicketFields"], in: app), "document field mapping missing")
            snap("shared-ticket-review-\(kind)")
            save.tap()
            let card = app.buttons["passCard"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10), "reviewed ticket not saved")
            card.tap()
            XCTAssertTrue(app.buttons["showOriginal"].waitForExistence(timeout: 10), "original missing")
            snap("shared-ticket-detail-\(kind)")
            app.terminate()
        }
        let ambiguous = launch(["PUBLIT_IMPORT_SAMPLE": "ambiguous"])
        XCTAssertTrue(ambiguous.buttons["ticketPage-0"].waitForExistence(timeout: 30), "multiple tickets need a page choice")
        snap("shared-ticket-pages")
        ambiguous.buttons["ticketPage-0"].tap()
        XCTAssertTrue(ambiguous.buttons["savePass"].waitForExistence(timeout: 30), "chosen page must be reviewed")
        ambiguous.terminate()
        let unknown = launch(["PUBLIT_IMPORT_SAMPLE": "unknown"])
        XCTAssertTrue(unknown.buttons["savePass"].waitForExistence(timeout: 30), "unknown file must go to review")
        XCTAssertFalse(unknown.staticTexts["sharedTicketAdded"].exists)
        snap("shared-ticket-review")
        unknown.buttons["Cancel"].firstMatch.tap()
    }

    /// F17 The field mapper is reachable from review and returns without persisting a draft.
    func testF17TicketFieldReview() {
        let app = launch(["PUBLIT_IMPORT_SAMPLE": "pdf"])
        XCTAssertTrue(app.buttons["savePass"].waitForExistence(timeout: 30))
        let mapping = app.buttons["mapTicketFields"]
        XCTAssertTrue(bringUp(mapping, in: app))
        mapping.tap()
        let text = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ticketText-")).firstMatch
        if text.waitForExistence(timeout: 20) {
            XCTAssertTrue(reveal(text, in: app))
            text.tap()
            XCTAssertTrue(app.textFields["ticketMappingText"].exists || app.textViews["ticketMappingText"].exists)
            app.buttons["ticketField-title"].tap()
        } else {
            // PDF text import still works when the simulator's Vision engine is unavailable.
            XCTAssertTrue(app.buttons["Done"].exists)
        }
        snap("ticket-field-mapper")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["savePass"].exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.buttons["savePass"].exists)
    }

    /// F18 Far from any stop (Cavallino-Treporti, 3 km from the Punta Sabbioni ferry; nothing within 1.5 km):
    /// the board lists the ferries with distance and walking time and says they are far, instead of an empty board.
    func testF18FarStopIsShownWithWalk() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("needs a simulated location") }
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 45.4560, longitude: 12.4600))
        defer { XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.13715, longitude: 11.57540)) }
        let app = launch()
        nudge(app)
        XCTAssertTrue(app.navigationBars["Nearby"].waitForExistence(timeout: 10))
        let note = app.descendants(matching: .any)["nearbyFarNote"]
        XCTAssertTrue(note.waitForExistence(timeout: timeout), "far stops not pointed out")
        XCTAssertTrue(note.label.contains("km"), note.label)
        XCTAssertTrue(app.descendants(matching: .any)["departureRow"].firstMatch.waitForExistence(timeout: 10),
                      "far departures not listed")
        XCTAssertFalse(app.staticTexts["No departures nearby"].exists)
        snap("nearby-far")
    }

    /// F19 Long press on the station map drops a pin with "Route here" and "Route from here", like Apple Maps.
    func testF19DropPinOnMap() {
        let app = launch()
        nudge(app)
        let mapButton = app.buttons["Station map"]
        XCTAssertTrue(mapButton.waitForExistence(timeout: 10))
        mapButton.tap()
        XCTAssertTrue(app.navigationBars["Stations"].waitForExistence(timeout: 10))
        sleep(3) // tiles
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)).press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["mapPlaceRoute"].waitForExistence(timeout: 10), "no place sheet after long press")
        XCTAssertTrue(app.buttons["mapPlaceRouteFrom"].exists)
        snap("map-dropped-pin")
        app.buttons["mapPlaceRoute"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 10))
    }

    /// F20 A pasted Google Maps link in the destination search is the place it points to.
    func testF20PastedMapLinkIsAPlace() {
        let app = launch(["PUBLIT_TAB": "plan"])
        let to = app.buttons["endpoint-to"]
        XCTAssertTrue(to.waitForExistence(timeout: 10), "no To field in Plan")
        to.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("https://www.google.com/maps/search/48.1351,+11.5820")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Place from the link'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 15), "pasted map link not recognised")
        snap("search-map-link")
    }
}
