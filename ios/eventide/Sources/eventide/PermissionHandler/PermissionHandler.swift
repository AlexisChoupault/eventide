//
//  PermissionHandler.swift
//  eventide
//
//  Created by CHOUPAULT Alexis on 02/01/2025.
//

import Foundation
import EventKit

class PermissionHandler: PermissionHandlerProtocol {
    private let eventStore: EKEventStore
    
    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }
    
    func checkCalendarAccessThenExecute(
        _ accessLevel: AccessLevel,
        onPermissionGranted permissionsGrantedCallback: @escaping () -> Void,
        onPermissionRefused permissionsRefusedCallback: @escaping () -> Void,
        onPermissionError errorCallback: @escaping (any Error) -> Void
    ) {
        let handler: (Result<Bool, any Error>) -> Void = { result in
            switch (result) {
            case .success(let granted):
                if (granted) {
                    permissionsGrantedCallback()
                } else {
                    permissionsRefusedCallback()
                }
            case .failure(let error):
                errorCallback(error)
            }
        }
        
        switch accessLevel {
        case .writeOnly: requestWriteOnlyAccess(completion: handler)
        case .fullAccess: requestFullAccess(completion: handler)
        }
    }
    
    private func requestWriteOnlyAccess(completion: @escaping (Result<Bool, any Error>) -> Void) {
        let handler: EKEventStoreRequestAccessCompletionHandler = { isGranted, error in
            guard error == nil else {
                completion(.failure(
                    PigeonError(
                        code: "GENERIC_ERROR",
                        message: "An error occurred during calendar access request.",
                        details: error!.localizedDescription
                    )
                ))
                return
            }
            
            completion(.success(isGranted))
        }
        
        if #available(iOS 17, *) {
            eventStore.requestWriteOnlyAccessToEvents(completion: handler)
        } else {
            eventStore.requestAccess(to: .event, completion: handler)
        }
    }
    
    private func requestFullAccess(completion: @escaping (Result<Bool, any Error>) -> Void) {
        let handler: EKEventStoreRequestAccessCompletionHandler = { isGranted, error in
            guard error == nil else {
                completion(.failure(
                    PigeonError(
                        code: "GENERIC_ERROR",
                        message: "An error occurred during calendar access request.",
                        details: error!.localizedDescription
                    )
                ))
                return
            }
            
            completion(.success(isGranted))
        }
        
        if #available(iOS 17, *) {
            eventStore.requestFullAccessToEvents(completion: handler)
        } else {
            eventStore.requestAccess(to: .event, completion: handler)
        }
    }
}
