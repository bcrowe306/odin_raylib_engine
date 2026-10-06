package engine

import "core:log"
import "core:crypto"
import "core:encoding/uuid"

ListenerId :: uuid.Identifier

EventValue :: union {
	int,
	f32,
	f64,
	bool,
	u32,
	u64,
}

EventSubscription :: struct {
	id: uuid.Identifier,
	userData: rawptr,
	callback: proc(source: rawptr, value: EventValue, gameContext: ^GameContext, user_data: rawptr)
}

EventSubject :: struct {
	name: string,
	listeners: [dynamic]EventSubscription,
	subscribe: proc(subject: ^EventSubject, callback: proc(source: rawptr, value: EventValue,  gameContext: ^GameContext, user_data: rawptr), user_data: rawptr ) -> ListenerId,
	unsubscribe: proc(subject: ^EventSubject, id: ListenerId),
	notify: proc(subject: ^EventSubject, source: rawptr, value: EventValue, gameContext: ^GameContext),
}


InitializeSubject :: proc(subject: ^EventSubject) {
	subject.notify = Notify
	subject.subscribe = Subscribe
	subject.unsubscribe = UnSubscribe
}


Subscribe :: proc(subject: ^EventSubject, callback: proc(source: rawptr, value: EventValue,  gameContext: ^GameContext, user_data: rawptr), user_data: rawptr ) -> ListenerId {
	context.random_generator = crypto.random_generator()
	id := uuid.generate_v4()
	subscription := EventSubscription{
		id = id,
		userData = user_data,
		callback = callback
	}
	_, err := append(&subject.listeners, subscription)
	if err != nil {
		log.error(err)
	}
	return id
}

Notify :: proc(subject: ^EventSubject, source: rawptr, value: EventValue, gameContext: ^GameContext) {
	if subject != nil {
		for listener in subject.listeners {
			if listener.callback != nil {
				listener.callback(source, value, gameContext, listener.userData)
			}
			else {
				log.errorf("Listener callback is nil")
			}
		}
	}
}

UnSubscribe :: proc(subject: ^EventSubject, id: ListenerId) {
	index := -1
	for listener, i in subject.listeners {
		if listener.id == id {
			index = i
			break
		}
	}
	if index != -1 {
		unordered_remove(&subject.listeners, index)
	}
	else {
		log.error("Cannot unsubscribe. ListenerId not found. ", id )
	}
}
