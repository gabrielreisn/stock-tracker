import { useSyncExternalStore } from 'react';

/** A small piece of state that lives outside React, read from components with `useValue`. */
export function createStore<State extends object>(initial: State) {
  let state = initial;
  const listeners = new Set<() => void>();

  function subscribe(listener: () => void) {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }

  return {
    get: () => state,
    set(patch: Partial<State>) {
      state = { ...state, ...patch };
      listeners.forEach((listener) => listener());
    },
    useValue: () => useSyncExternalStore(subscribe, () => state),
  };
}
