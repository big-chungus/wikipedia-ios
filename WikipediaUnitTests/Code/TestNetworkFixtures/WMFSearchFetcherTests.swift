import Foundation
import Testing
@testable import Wikipedia
@testable import WMF

struct WMFSearchFetcherTests {
    @Test
    func nonEmptyPrefixResponse() async throws {
        let json = try jsonFixture(named: "BarackSearch")
        let harness = makeHarness()
        defer {
            harness.fetcher.cancelAllFetches()
        }
        harness.httpClient.responseData = try JSONSerialization.data(withJSONObject: json)
        let siteURL = try #require(URL(string: "https://en.wikipedia.org"))

        let result = try await harness.fetcher.fetchArticles(forSearchTerm: "foo", siteURL: siteURL, resultLimit: 15)

        let query = json["query"] as? [String: Any]
        let pages = query?["pages"] as? [String: Any]
        #expect(result.results?.count == pages?.count)
        #expect(harness.httpClient.capturedRequests.containsPrefixSearchRequest)
    }

    @Test
    func emptyPrefixResponse() async throws {
        let json = try jsonFixture(named: "NoSearchResultsWithSuggestion")
        let harness = makeHarness()
        defer {
            harness.fetcher.cancelAllFetches()
        }
        harness.httpClient.responseData = try JSONSerialization.data(withJSONObject: json)
        let siteURL = try #require(URL(string: "https://en.wikipedia.org"))

        let result = try await harness.fetcher.fetchArticles(forSearchTerm: "foo", siteURL: siteURL, resultLimit: 15)

        let query = json["query"] as? [String: Any]
        let searchInfo = query?["searchinfo"] as? [String: Any]
        #expect(result.searchSuggestion == searchInfo?["suggestion"] as? String)
        #expect(result.results?.count == 0)
        #expect(harness.httpClient.capturedRequests.containsPrefixSearchRequest)
    }

    private func makeHarness() -> (fetcher: WMFSearchFetcher, httpClient: SearchHTTPClient) {
        let httpClient = SearchHTTPClient()
        let session = Session(configuration: .current, httpClientProvider: SearchHTTPClientProvider(httpClient: httpClient))
        let fetcher = WMFSearchFetcher(session: session, configuration: .current)
        return (fetcher, httpClient)
    }

    private func jsonFixture(named name: String) throws -> [String: Any] {
        let data = try #require(Bundle(for: WMFSearchFetcherTestBundleToken.self).wmf_data(fromContentsOfFile: name, ofType: "json"))
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        return try #require(jsonObject as? [String: Any])
    }
}

struct SearchRecoveryTests {
    @Test
    func visibilityRequiresCompletedZeroResults() {
        #expect(SearchResultsDisplayState.history.showsSearchRecovery == false)
        #expect(SearchResultsDisplayState.loading.showsSearchRecovery == false)
        #expect(SearchResultsDisplayState.completed(resultCount: 1).showsSearchRecovery == false)
        #expect(SearchResultsDisplayState.failed(.noSearchResults).showsSearchRecovery == false)
        #expect(SearchResultsDisplayState.completed(resultCount: 0).showsSearchRecovery)

        #expect(SearchResultsDisplayState.history.emptyViewType == .none)
        #expect(SearchResultsDisplayState.loading.emptyViewType == .none)
        #expect(SearchResultsDisplayState.completed(resultCount: 1).emptyViewType == .none)
        #expect(SearchResultsDisplayState.failed(.noSearchResults).emptyViewType == .noSearchResults)
        #expect(SearchResultsDisplayState.completed(resultCount: 0).emptyViewType == .noSearchResultsWithAction)
    }

    @MainActor
    @Test
    func surpriseMeTriggersNavigationForCurrentSearchLanguage() throws {
        let expectedSiteURL = try #require(URL(string: "https://es.wikipedia.org"))
        let controller = SearchResultsViewController(source: .searchTab, dataStore: MWKDataStore.shared())
        var openedSiteURL: URL?
        controller.randomArticleAction = { openedSiteURL = $0 }
        controller.resultsViewController.searchSiteURL = expectedSiteURL

        controller.transition(to: .loading)
        controller.didTapSurpriseMe()
        #expect(openedSiteURL == nil)

        controller.transition(to: .completed(resultCount: 0))
        controller.didTapSurpriseMe()
        #expect(openedSiteURL == expectedSiteURL)
    }
}

private final class WMFSearchFetcherTestBundleToken {}

private extension WMFSearchFetcher {
    func fetchArticles(forSearchTerm searchTerm: String, siteURL: URL, resultLimit: UInt) async throws -> WMFSearchResults {
        try await withCheckedThrowingContinuation { continuation in
            fetchArticles(forSearchTerm: searchTerm, siteURL: siteURL, resultLimit: resultLimit, failure: { error in
                continuation.resume(throwing: error)
            }, success: { result in
                continuation.resume(returning: result)
            })
        }
    }
}
