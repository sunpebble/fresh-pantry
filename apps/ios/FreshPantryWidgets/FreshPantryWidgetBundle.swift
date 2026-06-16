import SwiftUI
import WidgetKit

@main
struct FreshPantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExpiringWidget()
        MealPlanWidget()
        ShoppingWidget()
        WasteWidget()
    }
}
