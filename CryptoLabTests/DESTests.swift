//
//  DESTests.swift
//  CryptoLab
//
//  Created by Branko Popovic on 3/20/17.
//  Copyright © 2017 Branko Popovic. All rights reserved.
//

import XCTest
import CryptoLab

class DESTests: XCTestCase {
	
	var key	=			Data(bytes: [0x5f, 0xf5, 0x0c, 0x5b, 0x60, 0x96, 0x84])//, 0xa2, 0x35, 0xd5, 0xc5, 0xbf, 0x24, 0x69, 0x40, 0x8a, 0x5f, 0xf5, 0x0c, 0x5b, 0x60, 0x96, 0x84, 0xa2, 0x35, 0xd5, 0xc5, 0xbf, 0x24, 0x69, 0x40, 0x8a])
	var genericIV =		Data(bytes: [0x4f, 0x83, 0x51, 0xae, 0x1c, 0x48, 0xf4, 0x81])// 0x65, 0xf8, 0x1b, 0x53, 0x3d, 0xd6, 0xd9, 0x1f])
	var testData =		Data(bytes: [0xeb, 0xf9, 0x91, 0x42, 0x6a, 0x3f, 0x1b, 0x5f, 0xeb, 0xf9, 0x91, 0x42, 0x6a, 0x3f, 0x1b, 0x5f])//, 0x5d, 0x7e, 0x4e, 0xa1, 0x35, 0xe2, 0xe5, 0x01, 0x27, 0xe7, 0x5d, 0x8f, 0x41, 0xbb, 0x09, 0x9b, 0xb7, 0x98, 0x5c, 0x2a, 0x99, 0x33, 0x8a, 0x8a])
	
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
	
//	func testDES() {
//		do {
//			let encIV =		Data(bytes: [0x4f, 0x83, 0x51, 0xae, 0x1c, 0x48, 0xf4, 0x81])
//			let decIV =		Data(bytes: [0x4f, 0x83, 0x51, 0xae, 0x1c, 0x48, 0xf4, 0x81])
//			
//			let desE = try DESCipher(key: key, iv: encIV, blockMode: .cbc)
//			let desD = try DESCipher(key: key, iv: decIV, blockMode: .cbc)
//			
//			let encryption = try desE.encrypt(data: testData)
//			let decryption = try desD.decrypt(data: encryption)
//			XCTAssert(testData == decryption, "DSA Fail")
//		}
//		catch let err {
//			XCTFail("DES Fail: \(err)")
//		}
//	}
}
