//
//  ARSessionPublisher.swift
//  Example
//
//  Created by Reza Ali on 4/26/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//
/*
 MIT License

 Copyright (c) 2023 Hi-Rez

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

#if os(iOS)

import ARKit
import Combine
import Foundation

@available(iOS 14.0, *)
public class ARSessionPublisher: NSObject, ARSessionDelegate {
    public weak var session: ARSession?
    
    public let addedAnchors = PassthroughSubject<[ARAnchor], Never>()
    
    public let updatedAnchors = PassthroughSubject<[ARAnchor], Never>()
    
    public let removedAnchors = PassthroughSubject<[ARAnchor], Never>()
    
    public let updatedFrame = PassthroughSubject<ARFrame, Never>()
    
    public let cameraTrackingState = PassthroughSubject<ARCamera, Never>()
    
    public let geoTrackingStatus = PassthroughSubject<ARGeoTrackingStatus, Never>()
    
    public let sessionWasInterrupted = PassthroughSubject<ARSession, Never>()
    
    public let sessionInterruptionEnded = PassthroughSubject<ARSession, Never>()
    
    public let audioSampleBufferOutput = PassthroughSubject<CMSampleBuffer, Never>()
    
    public let sessionFailure = PassthroughSubject<Error, Never>()
    
    public let collaborationDataOutput = PassthroughSubject<ARSession.CollaborationData, Never>()
    
    public var shouldSessionAttemptRelocalization: (@Sendable (ARSession) -> Bool)?
    
    public init(session: ARSession,
                shouldSessionAttemptRelocalization: (@Sendable (ARSession) -> Bool)? = nil) {
        self.session = session
        self.shouldSessionAttemptRelocalization = shouldSessionAttemptRelocalization
        super.init()
        session.delegate = self
    }
    
    // MARK: - ARSessionDelegate
    
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        addedAnchors.send(anchors)
    }
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updatedAnchors.send(anchors)
    }
    
    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        removedAnchors.send(anchors)
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updatedFrame.send(frame)
    }
    
    // MARK: - ARSessionObserver
    
    public func session(
        _ session: ARSession,
        cameraDidChangeTrackingState camera: ARCamera
    ) {
        cameraTrackingState.send(camera)
    }
    
    public func session(
        _ session: ARSession,
        didChange geoTrackingStatus: ARGeoTrackingStatus
    ) {
        self.geoTrackingStatus.send(geoTrackingStatus)
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        sessionWasInterrupted.send(session)
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        sessionInterruptionEnded.send(session)
    }
    
    public func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return shouldSessionAttemptRelocalization?(session) ?? true
    }
    
    public func session(
        _ session: ARSession,
        didOutputAudioSampleBuffer audioSampleBuffer: CMSampleBuffer
    ) {
        audioSampleBufferOutput.send(audioSampleBuffer)
    }
    
    public func session(
        _ session: ARSession,
        didFailWithError error: Error
    ) {
        sessionFailure.send(error)
    }
    
    public func session(
        _ session: ARSession,
        didOutputCollaborationData data: ARSession.CollaborationData
    ) {
        collaborationDataOutput.send(data)
    }
}

#endif
