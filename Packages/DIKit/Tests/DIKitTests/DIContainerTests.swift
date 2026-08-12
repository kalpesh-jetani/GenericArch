import Testing
import Core
@testable import DIKit

private protocol Greeting: Sendable { var text: String { get } }
private struct LiveGreeting: Greeting { let text = "live" }
private struct MockGreeting: Greeting { let text = "mock" }

private enum GreetingKey: DependencyKey {
    static var liveValue: any Greeting { LiveGreeting() }
    static var testValue: any Greeting { MockGreeting() }
}

@Suite("DIContainer")
struct DIContainerTests {
    @Test("resolution is total — an unregistered key never traps")
    func unregisteredResolves() {
        let container = DIContainerBuilder(mode: .live).build()
        #expect(container[GreetingKey.self].text == "live")
    }

    @Test("test mode never falls through to liveValue")
    func testModeUsesTestValue() {
        let container = DIContainerBuilder(mode: .test).build()
        #expect(container[GreetingKey.self].text == "mock")
    }

    @Test("an explicit registration wins over both defaults")
    func registrationWins() {
        var builder = DIContainerBuilder(mode: .test)
        builder.register(GreetingKey.self, LiveGreeting())
        #expect(builder.build()[GreetingKey.self].text == "live")
    }

    @Test("the built container is Sendable and crosses an actor boundary")
    func containerIsSendable() async {
        let container = DIContainerBuilder(mode: .test).build()
        let actorRef = Holder()
        await actorRef.store(container)
        #expect(await actorRef.resolvedText == "mock")
    }
}

private actor Holder {
    private var container: DIContainer?
    /// Stores the container inside the actor, forcing it across an isolation boundary.
    func store(_ c: DIContainer) { container = c }

    /// Resolves from inside the actor, proving the frozen container is usable there.
    var resolvedText: String { container?[GreetingKey.self].text ?? "none" }
}
