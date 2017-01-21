//
//  RequestPool.swift
//  SwiftLocation
//
//  Created by Daniele Margutti on 18/01/2017.
//  Copyright © 2017 Daniele Margutti. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit


/// Conformance protocol
internal protocol RequestsPoolProtocol: CustomStringConvertible {
	typealias PoolChange = ((Any) -> (Void))

	var requiredAuthorization: Authorization { get }
	func dispatch(error: Error)
	func dispatch(value: Any)
	func set(_ newState: RequestState, forRequestsIn states: Set<RequestState>)
	
	var onRemove: PoolChange? { get set }
	var onAdd: PoolChange? { get set }
	
	var countRunning: Int { get }
	var countPaused: Int { get }
	var count: Int { get }
	
	func resumeWaitingAuth()
}


/// This class represent a pool of requests.
/// Each object must be conform to `Request` protocol.
internal class RequestsPool<T: Request> : RequestsPoolProtocol, Sequence {
	
	/// List of requests in queue
	private var list: Set<T> = []
	
	/// Return the number of queued requests
	public var count: Int {
		return list.count
	}
	
	/// Return the number of paused requests
	public var countPaused: Int {
		return list.reduce(0, { return $0 + ($1.state.isPaused ? 1 : 0) } )
	}
	
	/// Return the number of currently running requests
	public var countRunning: Int {
		return list.reduce(0, { return $0 + ($1.state.isRunning ? 1 : 0) } )
	}

	/// Callback called when an item was removed from the list
	public var onRemove: RequestsPoolProtocol.PoolChange? = nil
	
	/// Callback called when a new item is added to the list
	public var onAdd: RequestsPoolProtocol.PoolChange? = nil
	
	/// Add a new request to the pool
	///
	/// - Parameter item: request to append
	/// - Returns: `true` if request is added, `false` if it's already part of the queue
	@discardableResult
	public func add(_ item: T) -> Bool {
		guard !self.isQueued(item) else { return false }
		list.insert(item)
		onAdd?(item)
		return true
	}
	
	/// Remove a queued request from the pool
	///
	/// - Parameter item: request to remove
	/// - Returns: `true` if request was part of the queue, `false` otherwise
	@discardableResult
	public func remove(_ item: T) -> Bool {
		guard self.isQueued(item) else { return false }
		list.remove(item)
		onRemove?(item)
		return true
	}
	
	/// Return `true` if the request is part of the queue.
	///
	/// - Parameter item: request
	/// - Returns: `true` if request is part of the queue, `false` otherwise.
	public func isQueued(_ item: T) -> Bool {
		return list.contains(item)
	}
	
	
	/// Conform to `Sequence` protocol
	///
	/// - Returns: iterator for set
	public func makeIterator() -> Set<T>.Iterator {
		return list.makeIterator()
	}
	
	public func set(_ newState: RequestState, forRequestsIn states: Set<RequestState>) {
		list.forEach {
			if let request = $0 as? LocationRequest {
				if states.contains($0.state) {
					request._state = newState
				}
			}
		}
	}
	
	/// Dispatch an error to all running requests
	///
	/// - Parameter error: error to dispatch
	public func dispatch(error: Error) {
		iterate({ $0.state.isRunning }, { $0.dispatch(error: error) })
	}
	
	
	/// Iterate over request which are the state listed above
	///
	/// - Parameters:
	///   - states: compatible state
	///   - iteration: iteration block
	public func iterate(_ states: Set<RequestState>, _ iteration: ((T) -> (Void))) {
		list.forEach {
			if states.contains($0.state) {
				iteration($0)
			}
		}
	}
	
	
	/// Iterate over requests from pool which validate proposed condition
	///
	/// - Parameters:
	///   - validation: validation handler
	///   - iteration: iteraor
	public func iterate(_ validation: ((T) -> (Bool)), _ iteration: ((T) -> (Void))) {
		list.forEach {
			if validation($0) {
				iteration($0)
			}
		}
		
	}
	
	
	/// Resume any waiting for auth request
	public func resumeWaitingAuth() {
		self.iterate({ request in
			return request.state == RequestState.waitingUserAuth
		}) { request in
			request.resume()
		}
	}
	
	/// Dispatch a value to all running requests
	///
	/// - Parameter value: value to dispatch
	public func dispatch(value: Any) {
		// Heading request
		if T.self is HeadingRequest.Type, let v = value as? CLHeading {
			iterate({ $0.state.isRunning }, { ($0 as! HeadingRequest).dispatch(heading: v) })
			list.forEach { ($0 as! HeadingRequest).dispatch(heading: v) }
		}
		// Location request
		else if T.self is LocationRequest.Type, let v = value as? CLLocation {
			iterate({ $0.state.isRunning }, { ($0 as! LocationRequest).dispatch(location: v) })
		}
		// Region request
		else if T.self is RegionRequest.Type {
			if let v = value as? RegionEvent {
				iterate({ $0.state.isRunning }, { ($0 as! RegionRequest).dispatch(event: v) })
			}
			else if let v = value as? CLRegionState {
				iterate({ $0.state.isRunning }, { ($0 as! RegionRequest).dispatch(state: v) })
			}
		}
	}
	
	
	/// Return `true` if pool contains at least one background request type
	///
	/// - Returns: `true` or `false`
	public func hasBackgroundRequests() -> Bool {
		for request in list {
			if request.isBackgroundRequest {
				return true
			}
		}
		return false
	}
	
	/// Return the minimum allowed authorization we should require to allow
	/// currently queued and running requests
	public var requiredAuthorization: Authorization {
		let auth = list.reduce(.none) { $0 < $1.requiredAuth ? $0 : $1.requiredAuth }
		return auth
	}
	
	var description: String {
		let typeName = String(describing: type(of: T.self))
		return "Pool of \(typeName): \(self.count) total (\(self.countRunning) running, \(self.countPaused) paused)"
	}
}
