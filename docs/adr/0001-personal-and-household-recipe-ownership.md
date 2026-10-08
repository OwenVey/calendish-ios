# Personal and household recipe ownership

Recipes can belong to a person or a household, while groceries and meal plans belong to a household. Personal recipes remain with their owners through household changes; sharing grants the current household access to the same original, and only its owner can edit that original. When an owner leaves or is removed, their shared recipes become independent household copies so the departing person keeps their collection and the household retains usable recipes and meal plans.

Existing personal recipes become shared when their owner joins a household, and newly created or imported personal recipes start shared with an "Only me" option. Other members can save their own copies to adapt a personal recipe. Saved copies start "Only me" to avoid immediately adding duplicate shared recipes; their owners may explicitly share them later. One recipe browser offers All, Mine, and Household filters; Mine and Household may overlap for a shared personal recipe. All includes personal recipes and recipes available to the household, Mine includes recipes the person owns, and Household includes shared personal recipes and household-owned recipes. Personal recipes identify their owner, while household-owned recipes are labeled "Household."

Each person belongs to one household; joining another replaces their current membership. All members may edit household-owned recipes, groceries, and meal plans. Household ownership governs membership management rather than exclusive control of cooking content.

Unsharing also leaves an independent household copy. "Only me" ends access to the personal original and its future changes; it does not retract previously shared content. The UI must explain this lasting contribution when recipes are first shared and when sharing ends.

Deleting a shared personal original also preserves an independent household copy, with that consequence explained in the deletion confirmation. Members can separately delete the household copy. Joining or leaving offers an optional, unchecked "Save household recipes to my collection" action that saves all household-owned recipes as personal copies; individual recipes can also be saved from their detail screens.

Planning a meal captures the recipe version and serving count. Subsequent recipe edits or deletion do not change that planned meal or groceries already added. A person may explicitly update a planned meal to the latest recipe version.

We chose this over exclusively household-owned recipes, which would make people lose access to their collections when changing households, and exclusively personal recipes with access revoked on departure, which would disrupt the household's cooking history. Development data may be wiped if needed; preserving or assigning personal owners to legacy recipe rows is outside this redesign.
