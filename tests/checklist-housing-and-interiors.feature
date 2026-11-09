# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_doorlock — Housing & Interiors

  @kora_doorlock @checklist @checklist:kora_doorlock:toggle-door-e @cat:housing-and-interiors
  Scenario: Lock/unlock a door with E
    """
    Checklist test: Stand near a configured door as an authorised player, press E (rebindable keybind) and see the door lock/unlock with sound.
    """
    When I manually: go to a configured door I am authorised to use
    And I press the "E" key
    Then I confirm: the door locks or unlocks
    And I confirm: I hear the lock/unlock sound
    When I press the "E" key
    Then I confirm: the door toggles back to the opposite state

  @kora_doorlock @checklist @checklist:kora_doorlock:door-prompt-ui @cat:housing-and-interiors
  Scenario: Door prompt shows lock/unlock state
    """
    Checklist test: Walk to a door: prompt reads Lock Door / Unlock Door (generic text) and updates after toggling; hidden if hideUi is set.
    """
    When I manually: walk up to a door within interaction distance
    Then the text UI should show "Lock Door"
    And I confirm: the prompt reads "Lock Door" or "Unlock Door" (generic text, no door name)
    When I press the "E" key
    Then I confirm: the prompt text updates to the opposite state
    And I confirm: the prompt is hidden on a door that has hideUi set (only applies if such a door exists; otherwise mark Pass)

  @kora_doorlock @checklist @checklist:kora_doorlock:access-denied @cat:housing-and-interiors
  Scenario: Unauthorised player is refused
    """
    Checklist test: Try E on a job/gang door without the job: access-denied notification and door state resyncs to the real state.
    """
    Given my job is "unemployed"
    And my gang is "none"
    When I manually: go to a door restricted to a job or gang
    And I press the "E" key
    Then I confirm: I see an access-denied notification
    And I confirm: the door state shown resyncs to the real state of the door

  @kora_doorlock @checklist @checklist:kora_doorlock:job-gang-grade-access @cat:housing-and-interiors
  Scenario: Job/gang minimum-grade access
    """
    Checklist test: On a door with groups, test with matching job below and at the required grade; only the required grade opens it.
    """
    When I manually: go to a door that has groups (job or gang with a minimum grade) and note the required job/gang and grade
    And I manually: get the matching job or gang at a grade below the required grade
    And I press the "E" key
    Then I confirm: the door does not lock or unlock
    When I manually: get the matching job or gang at exactly the required grade
    And I press the "E" key
    Then I confirm: the door locks or unlocks

  @kora_doorlock @checklist @checklist:kora_doorlock:key-item-access @cat:housing-and-interiors
  Scenario: Key item access (consumable or kept)
    """
    Checklist test: Give the door's key item (with metadata type if set) and open it; a remove=true key is used up, others stay.
    """
    When I manually: get the key item configured for a key-item door (with the metadata type if set)
    And I manually: go to that door
    And I press the "E" key
    Then I confirm: the door locks or unlocks
    And I confirm: a key item with remove=true is used up from my inventory
    And I confirm: a key item without remove=true stays in my inventory

  @kora_doorlock @checklist @checklist:kora_doorlock:passcode-access @cat:housing-and-interiors
  Scenario: Passcode entry
    """
    Checklist test: On a passcode door press E and enter the code; the right code toggles, a wrong code is refused.
    """
    When I manually: go to a passcode door
    And I press the "E" key
    Then I confirm: a passcode entry prompt opens
    When I manually: enter the correct code
    Then I confirm: the door toggles
    When I press the "E" key
    And I manually: enter a wrong code
    Then I confirm: the code is refused and the door does not change

  @kora_doorlock @checklist @checklist:kora_doorlock:character-id-access @cat:housing-and-interiors
  Scenario: Character ID access
    """
    Checklist test: Add your character ID to a door in the creator and confirm you can open it while other characters cannot.
    """
    When I manually: ask an admin to add my character ID to a door in the /doorlocks creator
    And I manually: go to that door
    And I press the "E" key
    Then I confirm: the door locks or unlocks for me
    When I manually: ask a second player with a different character to press E on the same door
    Then I confirm: the other player is refused

  @kora_doorlock @checklist @checklist:kora_doorlock:lockpick-door @cat:housing-and-interiors
  Scenario: Lockpick a door
    """
    Checklist test: With a lockpick item, use the target option on a lockpickable door or the pickClosestDoor export; minigame runs, item may break.
    """
    Given I have 1 "lockpick"
    When I manually: go to a lockpickable locked door
    And I manually: select the lockpick target option on the door
    Then a progress bar should run
    And I confirm: the lockpick minigame runs
    And I confirm: the lockpick may break afterwards
    And I confirm: the door unlocks on success

  @kora_doorlock @checklist @checklist:kora_doorlock:lockpick-rate-limit @cat:housing-and-interiors
  Scenario: Lockpick rate limit
    """
    Checklist test: Spam lockpick attempts (more than 4 in 10s) and confirm further attempts are throttled.
    """
    Given I have 50 "lockpick"
    When I manually: go to a lockpickable locked door
    And I manually: start lockpick attempts more than 4 times within 10 seconds
    Then I confirm: further attempts beyond 4 in 10 seconds are refused or throttled

  @kora_doorlock @checklist @checklist:kora_doorlock:auto-lock @cat:housing-and-interiors
  Scenario: Auto-lock timer
    """
    Checklist test: Unlock a door with autoLock set and wait; it relocks by itself after the configured seconds.
    """
    When I manually: go to a door with autoLock set
    And I press the "E" key
    And I manually: wait for the configured auto-lock time
    Then I confirm: the door relocks by itself after the configured seconds

  @kora_doorlock @checklist @checklist:kora_doorlock:double-door @cat:housing-and-interiors
  Scenario: Double doors move together
    """
    Checklist test: Use a double door (two leaves) and confirm both leaves lock/unlock and open as one.
    """
    When I manually: go to a double door (two leaves)
    And I press the "E" key
    Then I confirm: both leaves lock or unlock together
    When I manually: open the door
    Then I confirm: both leaves open as one

  @kora_doorlock @checklist @checklist:kora_doorlock:linked-doors @cat:housing-and-interiors @needs:admin @manual
  Scenario: Linked doors toggle together
    """
    Checklist test: Link two doors in the creator, toggle one and confirm the other follows.
    """
    When I manually: type /doorlocks in chat and open a door page
    And I manually: link two doors in the creator
    And I manually: toggle one of the linked doors
    Then I confirm: the other linked door locks or unlocks together with it

  @kora_doorlock @checklist @checklist:kora_doorlock:door-state-persist @cat:housing-and-interiors @manual
  Scenario: Door state restored for new players
    """
    Checklist test: Toggle a door, then have another player join/approach; they see the current lock state.
    """
    When I manually: toggle a door lock state
    And I manually: ask a second player to join or approach the door
    Then I confirm: the other player sees the door in its current lock state

  @kora_doorlock @checklist @checklist:kora_doorlock:creator-menu @cat:housing-and-interiors @needs:admin
  Scenario: /doorlocks creator (admin)
    """
    Checklist test: As admin run /doorlocks (or /doorlocks closest): searchable door grid, Closest to me sort, Refresh, per-door pages.
    """
    When I run the command "/doorlocks"
    Then the "qbdoorlock:creator" app opens
    And I confirm: a searchable door grid is shown
    When I manually: use the Closest to me sort
    Then I confirm: doors are sorted with the closest one first
    When I manually: press Refresh
    Then I confirm: the door list refreshes
    When I manually: open a door's page
    Then I confirm: the per-door page opens
    When I manually: close the creator
    And I run the command "/doorlocks closest"
    Then the "qbdoorlock:creator" app opens

  @kora_doorlock @checklist @checklist:kora_doorlock:create-door @cat:housing-and-interiors @needs:admin
  Scenario: Create a door with /adddoor
    """
    Checklist test: Run /adddoor (aliases /newdoor, /doordebug), name it, aim at the door and press E (twice for double), Backspace cancels.
    """
    When I run the command "/adddoor"
    And I manually: press Create new door, type a name and choose a single door
    Then I confirm: the creator closes and the door I aim at is outlined
    When I manually: aim at the door and press E
    Then I confirm: the new door's page opens
    When I run the command "/newdoor"
    Then I confirm: the Create new door flow opens
    When I run the command "/doordebug"
    Then I confirm: the Create new door flow opens
    When I manually: create a double door, aim at the first leaf and press E, then aim at the second leaf and press E
    Then I confirm: the double door is created and its page opens
    When I manually: start creating a door and press Backspace
    Then I confirm: the creation is cancelled and no door is created

  @kora_doorlock @checklist @checklist:kora_doorlock:edit-door-settings @cat:housing-and-interiors @needs:admin @manual
  Scenario: Edit door details/access/lockpick/sounds
    """
    Checklist test: On a door page change distance, auto-lock, rate, hold open, jobs, gangs, chars, items, lockpick and sounds; changes persist.
    """
    When I manually: type /doorlocks in chat and open a door page
    And I manually: change distance, auto-lock, rate, hold open, jobs, gangs, chars, items, lockpick and sounds, and save
    Then I confirm: the door behaves according to the changed settings
    When I manually: refresh the door page
    Then I confirm: the changes persisted

  @kora_doorlock @checklist @checklist:kora_doorlock:admin-lock-teleport @cat:housing-and-interiors @needs:admin @manual
  Scenario: Admin lock/unlock and teleport from menu
    """
    Checklist test: From a door page, use Lock/Unlock and Teleport to door; admins can toggle any door from the menu.
    """
    When I manually: type /doorlocks in chat and open a door page
    And I manually: use Lock and Unlock on the door page
    Then I confirm: the door locks and unlocks from the menu, even when I have no access to it
    When I manually: use Teleport to door
    Then I confirm: I am teleported next to the door

  @kora_doorlock @checklist @checklist:kora_doorlock:duplicate-delete-door @cat:housing-and-interiors @needs:admin @manual
  Scenario: Duplicate and delete a door
    """
    Checklist test: Use Duplicate door (aim at new door) and Delete door on a door page; deleted config doors stay gone after restart.
    """
    When I manually: type /doorlocks in chat, open a door page and press Duplicate door
    And I manually: aim at the new door and press E
    Then I confirm: a duplicate door is created with the same settings
    When I manually: press Delete door on a door page and confirm
    Then I confirm: the door is removed from the list
    When I manually: ask a Mod to restart the resource if the deleted door was a config door
    Then I confirm: the deleted config door stays gone after restart

  @kora_doorlock @checklist @checklist:kora_doorlock:categories @cat:housing-and-interiors @needs:admin @manual
  Scenario: Door categories and Place doors
    """
    Checklist test: Create a category (e.g. Police) with defaults, press Place doors, aim and E for single then double doors; doors are named police-1, police-2.
    """
    When I manually: type /doorlocks in chat and create a category named Police with defaults
    And I manually: press Place doors, aim at a single door and press E
    And I manually: press Place doors again, choose double, aim at both leaves and press E for each
    Then I confirm: the doors are named police-1 and police-2

  @kora_doorlock @checklist @checklist:kora_doorlock:import-ox-doors @cat:housing-and-interiors @needs:admin @manual
  Scenario: /importoxdoors
    """
    Checklist test: As admin run /importoxdoors with an ox_doorlock table; existing IDs are skipped and a count is shown.
    """
    When I manually: make sure an ox_doorlock table exists in the database
    And I manually: run /importoxdoors
    Then I confirm: existing IDs are skipped and a count is shown

  @kora_doorlock @checklist @checklist:kora_doorlock:admin-bypass-off @cat:housing-and-interiors @needs:admin @manual
  Scenario: Admins do not bypass door access by default
    """
    Checklist test: As admin without door access try E on a restricted door: refused (unless AdminsBypassDoorAccess is on).
    """
    When I manually: as an admin without access to a restricted door, go to that door
    And I manually: press E on the door
    Then I confirm: the door does not toggle (only applies when Config.AdminsBypassDoorAccess is off; if on, mark Pass if the door toggles)

  @kora_doorlock @checklist @checklist:kora_doorlock:door-exports @cat:housing-and-interiors @needs:admin @manual
  Scenario: Client/server exports
    """
    Checklist test: Call getClosestDoorId, getDoorState, setDoorState, editDoor via a test script/console and confirm the door reacts.
    """
    When I manually: call getClosestDoorId, getDoorState, setDoorState and editDoor via a test script or console
    Then I confirm: each export returns a valid result
    And I confirm: the door reacts to setDoorState and editDoor
