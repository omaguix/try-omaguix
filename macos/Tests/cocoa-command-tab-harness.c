#include <ApplicationServices/ApplicationServices.h>
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#define kVK_Tab 0x30
static bool send_command_tab;
static bool command_tab_released;
static bool command_tab_release_armed;
static bool command_tab_key_passed;
/* TRACK */
/* LOG */
/* ROUTE */

/* Key codes and device flag bits as macOS reports them. */
enum { KEY_TAB = 0x30, KEY_T = 0x11, KEY_COMMAND = 0x37, KEY_SHIFT = 0x38,
       KEY_OPTION = 0x3a, KEY_CONTROL = 0x3b, KEY_RIGHT_OPTION = 0x3d };
#define LCTL (kCGEventFlagMaskControl | 0x1)
#define LALT (kCGEventFlagMaskAlternate | 0x20)
#define RALT (kCGEventFlagMaskAlternate | 0x40)
#define LCMD (kCGEventFlagMaskCommand | 0x8)
#define LSHIFT (kCGEventFlagMaskShift | 0x2)
#define CAPS kCGEventFlagMaskAlphaShift
#define FN kCGEventFlagMaskSecondaryFn
#define END { 0, 0, 0 }

typedef struct { CGEventType type; int key; CGEventFlags flags; } Step;

/* Feed a recorded sequence as the tap would; count completed chords. */
static int feed(const Step *steps)
{
    int completed_count = 0;

    for (; steps->type; steps++) {
        CGEventRef event = CGEventCreate(NULL);
        bool was_armed = command_tab_release_armed;
        bool completed;

        CGEventSetType(event, steps->type);
        CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, steps->key);
        /* Real flags-changed events carry the non-coalesced bit. */
        CGEventSetFlags(event, steps->flags | kCGEventFlagMaskNonCoalesced);
        completed = trackCommandTabRelease(steps->type, event);
        cocoa_tap_log_command_tab_release(steps->type, event, was_armed,
                                          completed);
        completed_count += completed;
        CFRelease(event);
    }
    return completed_count;
}

static bool released_after(const Step *steps)
{
    command_tab_released = false;
    command_tab_release_armed = false;
    feed(steps);
    return command_tab_released;
}

static bool route(CGEventType type, CGEventFlags flags)
{
    CGEventRef event = CGEventCreate(NULL);
    bool result;

    CGEventSetType(event, type);
    CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, KEY_TAB);
    CGEventSetFlags(event, flags);
    result = commandTabGoesToMacOS(type, event);
    CFRelease(event);
    return result;
}

#define FLAGS kCGEventFlagsChanged
#define DOWN kCGEventKeyDown
#define UP kCGEventKeyUp

int main(void)
{
    /* Control-Option pressed and released, one modifier at a time. */
    const Step clean[] = {
        { FLAGS, KEY_CONTROL, LCTL }, { FLAGS, KEY_OPTION, LCTL | LALT },
        { FLAGS, KEY_CONTROL, LALT }, { FLAGS, KEY_OPTION, 0 }, END };
    assert(released_after(clean));

    /* Recorded 2026-10-08 (launcher.log): Option first, Option up first. */
    const Step recorded[] = {
        { FLAGS, KEY_OPTION, LALT }, { FLAGS, KEY_CONTROL, LCTL | LALT },
        { FLAGS, KEY_OPTION, LCTL }, { FLAGS, KEY_CONTROL, 0 }, END };
    assert(released_after(recorded));

    /* Pressing the chord again while already released completes it again. */
    assert(feed(recorded) == 1 && command_tab_released);

    /* Caps Lock and fn do not change which modifiers make the chord. */
    const Step with_caps_and_fn[] = {
        { FLAGS, KEY_CONTROL, CAPS | FN | LCTL },
        { FLAGS, KEY_OPTION, CAPS | FN | LCTL | LALT },
        { FLAGS, KEY_OPTION, CAPS | FN | LCTL }, { FLAGS, KEY_CONTROL, CAPS | FN },
        END };
    assert(released_after(with_caps_and_fn));

    /* A key pressed with the chord makes it a shortcut, not the release. */
    const Step control_option_t[] = {
        { FLAGS, KEY_CONTROL, LCTL }, { FLAGS, KEY_OPTION, LCTL | LALT },
        { DOWN, KEY_T, LCTL | LALT }, { UP, KEY_T, LCTL | LALT },
        { FLAGS, KEY_OPTION, LCTL }, { FLAGS, KEY_CONTROL, 0 }, END };
    assert(!released_after(control_option_t));

    /* So is a key pressed while one chord modifier is still down. */
    const Step option_t_after_control_up[] = {
        { FLAGS, KEY_CONTROL, LCTL }, { FLAGS, KEY_OPTION, LCTL | LALT },
        { FLAGS, KEY_CONTROL, LALT }, { DOWN, KEY_T, LALT }, { UP, KEY_T, LALT },
        { FLAGS, KEY_OPTION, 0 }, END };
    assert(!released_after(option_t_after_control_up));

    /* Another modifier joining the full chord is a different chord. */
    const Step control_option_command[] = {
        { FLAGS, KEY_CONTROL, LCTL }, { FLAGS, KEY_OPTION, LCTL | LALT },
        { FLAGS, KEY_COMMAND, LCTL | LALT | LCMD },
        { FLAGS, KEY_OPTION, LCTL | LCMD }, { FLAGS, KEY_CONTROL, LCMD },
        { FLAGS, KEY_COMMAND, 0 }, END };
    assert(!released_after(control_option_command));

    /* A modifier held before the chord was complete keeps it from arming. */
    const Step shift_first[] = {
        { FLAGS, KEY_SHIFT, LSHIFT }, { FLAGS, KEY_CONTROL, LSHIFT | LCTL },
        { FLAGS, KEY_OPTION, LSHIFT | LCTL | LALT },
        { FLAGS, KEY_OPTION, LSHIFT | LCTL }, { FLAGS, KEY_CONTROL, LSHIFT },
        { FLAGS, KEY_SHIFT, 0 }, END };
    assert(!released_after(shift_first));

    /* One chord modifier alone is not the chord. */
    const Step control_alone[] = {
        { FLAGS, KEY_CONTROL, LCTL }, { FLAGS, KEY_CONTROL, 0 }, END };
    assert(!released_after(control_alone));

    /* Command-Tab itself, before the chord, keeps going to the guest. */
    const Step command_tab_only[] = {
        { FLAGS, KEY_COMMAND, LCMD }, { DOWN, KEY_TAB, LCMD },
        { UP, KEY_TAB, LCMD }, { FLAGS, KEY_COMMAND, 0 }, END };
    assert(!released_after(command_tab_only));

    /* Which Tab key events go to macOS rather than the guest. */
    #define ROUTE(type, flags) route(type, flags)
    send_command_tab = false;
    command_tab_key_passed = false;

    /* Quick Command-Tab with Command up before Tab: the key up follows. */
    assert(ROUTE(DOWN, LCMD));
    assert(ROUTE(UP, 0));
    /* Held Tab repeats as key downs, then one key up. */
    assert(ROUTE(DOWN, LCMD) && ROUTE(DOWN, LCMD) && ROUTE(UP, LCMD));
    /* Command-Shift-Tab goes to macOS too; a plain Tab stays with the guest. */
    assert(ROUTE(DOWN, LCMD | LSHIFT) && ROUTE(UP, LSHIFT));
    assert(!ROUTE(DOWN, 0) && !ROUTE(UP, 0));
    /* Tab pressed alone, Command added before its key up: still the guest's. */
    assert(!ROUTE(DOWN, 0) && !ROUTE(UP, LCMD));

    /* send-command-tab=on: the guest's until the release chord. */
    send_command_tab = true;
    command_tab_released = false;
    assert(!ROUTE(DOWN, LCMD) && !ROUTE(UP, 0));
    command_tab_released = true;
    assert(ROUTE(DOWN, LCMD) && ROUTE(UP, 0));

    puts("Command-Tab hand-back: all sequences behave");
    return 0;
}
