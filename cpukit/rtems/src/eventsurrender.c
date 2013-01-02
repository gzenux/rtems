/**
 *  @file
 *
 *  @brief Surrender Event
 *  @ingroup ClassicEvent
 */

/*
 *  COPYRIGHT (c) 1989-2008.
 *  On-Line Applications Research Corporation (OAR).
 *
 *  The license and distribution terms for this file may be
 *  found in the file LICENSE in this distribution or at
 *  http://www.rtems.com/license/LICENSE.
 */

#if HAVE_CONFIG_H
  #include "config.h"
#endif

#include <rtems/rtems/event.h>

void _Event_Surrender(
  Thread_Control                   *the_thread,
  rtems_event_set                   event_in,
  Event_Control                    *event,
  Thread_blocking_operation_States *sync_state,
  States_Control                    wait_state
)
{
  ISR_Level       level;
  rtems_event_set pending_events;
  rtems_event_set event_condition;
  rtems_event_set seized_events;
  rtems_option    option_set;

  option_set = the_thread->Wait.option;

  _ISR_Disable( level );
  _Event_sets_Post( event_in, &event->pending_events );
  pending_events  = event->pending_events;

  /*
   * At this point the event condition is a speculative quantity.  Later state
   * checks will show if the thread actually waits for an event.
   */
  event_condition = the_thread->Wait.count;

  seized_events = _Event_sets_Get( pending_events, event_condition );

  /*
   *  No events were seized in this operation
   */
  if ( _Event_sets_Is_empty( seized_events ) ) {
    _ISR_Enable( level );
    return;
  }

  /*
   *  If we are in an ISR and sending to the current thread, then
   *  we have a critical section issue to deal with.
   */
  if ( _ISR_Is_in_progress() &&
       _Thread_Is_executing( the_thread ) &&
       ((*sync_state == THREAD_BLOCKING_OPERATION_TIMEOUT) ||
        (*sync_state == THREAD_BLOCKING_OPERATION_NOTHING_HAPPENED)) ) {
    if ( seized_events == event_condition || _Options_Is_any(option_set) ) {
      event->pending_events = _Event_sets_Clear(
        pending_events,
        seized_events
      );
      the_thread->Wait.count = 0;
      *(rtems_event_set *)the_thread->Wait.return_argument = seized_events;
      *sync_state = THREAD_BLOCKING_OPERATION_SATISFIED;
    }
    _ISR_Enable( level );
    return;
  }

  /*
   *  Otherwise, this is a normal send to another thread
   */
  if ( _States_Are_set( the_thread->current_state, wait_state ) ) {
    if ( seized_events == event_condition || _Options_Is_any( option_set ) ) {
      event->pending_events = _Event_sets_Clear(
        pending_events,
        seized_events
      );
      the_thread->Wait.count = 0;
      *(rtems_event_set *)the_thread->Wait.return_argument = seized_events;

      _ISR_Flash( level );

      if ( !_Watchdog_Is_active( &the_thread->Timer ) ) {
        _ISR_Enable( level );
        _Thread_Unblock( the_thread );
      } else {
        _Watchdog_Deactivate( &the_thread->Timer );
        _ISR_Enable( level );
        (void) _Watchdog_Remove( &the_thread->Timer );
        _Thread_Unblock( the_thread );
      }
      return;
    }
  }
  _ISR_Enable( level );
}
