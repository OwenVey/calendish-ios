# Source groups for the swiftc-built logic tests. Each type lives in its own file,
# so a test names the groups it needs rather than individual files.
APP=calendish-ios
MODEL_SOURCES=($APP/{InterfaceCopy,Ingredient,MeasurementPreference,Recipe,RecipeCategory,RecipeOwner,RecipeScope,PlannedMeal,MealPlanNote,RecipeReview,GroceryItem,Household,HouseholdInvite,HouseholdMember,SampleRecipes,WeekStart,CalendarDays}.swift)
PREFERENCE_SOURCES=($APP/{PreferenceKey,RecipeSort,RecipeLayout,GroceryAutoClear,TimerAlert}.swift)
COOKED_HISTORY_SOURCES=($APP/{CookedHistory,RecipeCook,CookedDay,FinishedCook,FinishedCooks}.swift)
GROCERY_IMPORT_REVIEW_SOURCES=($APP/{GroceryImportReview,GroceryImportCandidate}.swift)
GROCERY_MERGE_SOURCES=($APP/{GroceryMerge,GroceryImport}.swift)
GROCERY_SYNC_SOURCES=($APP/{GrocerySync,GrocerySyncTransport,GroceryFields,GroceryMutation}.swift)
RECIPE_LINK_IMPORTER_SOURCES=($APP/{RecipeLinkImporter,ImportedRecipe,LoadedPage,PageLoader}.swift)
