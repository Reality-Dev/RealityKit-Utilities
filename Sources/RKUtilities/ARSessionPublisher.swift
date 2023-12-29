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

public class ARSessionPublisher: NSObject, ARSessionDelegate {
    public weak var session: ARSession?

    public let addedAnchorsPublisher = PassthroughSubject<[ARAnchor], Never>()
    
    public let updatedAnchorsPublisher = PassthroughSubject<[ARAnchor], Never>()
    
    public let removedAnchorsPublisher = PassthroughSubject<[ARAnchor], Never>()

    public let updatedFramePublisher = PassthroughSubject<ARFrame, Never>()

    public init(session: ARSession) {
        self.session = session
        super.init()
        session.delegate = self
    }

    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        addedAnchorsPublisher.send(anchors)
    }

    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updatedAnchorsPublisher.send(anchors)
    }

    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        removedAnchorsPublisher.send(anchors)
    }

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updatedFramePublisher.send(frame)
    }
}

#endif
