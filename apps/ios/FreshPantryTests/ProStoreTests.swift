import Testing
@testable import FreshPantry

@MainActor
struct ProStoreTests {
    @Test func unavailableProductStopsLoadingAndSurfacesError() async {
        let store = ProStore(productLoader: { nil })

        await store.loadProduct()

        #expect(store.product == nil)
        #expect(store.isLoadingProduct == false)
        #expect(store.didLoadProduct == true)
        #expect(store.purchaseError == "商品暂不可用，请稍后再试")
    }
}
