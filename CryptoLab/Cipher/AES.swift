//
//  Ciphers.swift
//  CryptoLab
//
//  Created by Branko Popovic on 2/9/17.
//  Copyright © 2017 Branko Popovic. All rights reserved.
//

import Foundation
import OpenSSL

enum AESKeySize: Int {
	case aes128 = 16
	case aes256 = 32
	case aes192 = 24
	
	public static func isAES128(keySize key: Int) -> Bool {
		return AESKeySize(rawValue: key) == AESKeySize.aes128
	}
	
	public static func isAES256(keySize key: Int) -> Bool {
		return AESKeySize(rawValue: key) == AESKeySize.aes256
	}
	
	public static func isAES192(keySize key: Int) -> Bool {
		return AESKeySize(rawValue: key) == AESKeySize.aes192
	}
}

public enum AESBlockCipherMode {
	case cbc
	case ecb
	case cfb
	case ofb //dont reuse iv
	case ctr //dont reuse iv
	
	public static func isBlockModeCBC(blockMode: AESBlockCipherMode) -> Bool {
		return .cbc == blockMode
	}
	public static func isBlockModeECB(blockMode: AESBlockCipherMode) -> Bool {
		return .ecb == blockMode
	}
	public static func isBlockModeCFB(blockMode: AESBlockCipherMode) -> Bool {
		return .cfb == blockMode
	}
	public static func isBlockModeOFB(blockMode: AESBlockCipherMode) -> Bool {
		return .ofb == blockMode
	}
	public static func isBlockModeCTR(blockMode: AESBlockCipherMode) -> Bool {
		return .ctr == blockMode
	}
}

enum AESError: Error {
	case noInitParameters(reason: String)
}

enum CipherGeneralError: Error {
	case cipherProcessFail(reason: String)
	case invalidKey(reason: String)
}

public class AESCipher: NSObject {
	
	public var iv: Data? {
		return coreCipher.iv
	}
	
	public var key: Data? {
		return coreCipher.key
	}
	
	fileprivate let coreCipher: AESCoreCipher
	
	public init(key: Data, iv: Data, blockMode: AESBlockCipherMode) throws {
		do {
			coreCipher = try AESCoreCipher(key: key, iv: iv, blockMode: blockMode)
		}
		catch let error {
			throw error
		}
		
		super.init()
	}
	
	public func makeBlockEncryptor() -> AESBlockEncryption {
		return AESBlockEncryption(aesCipher: self)
	}
	
	public func encrypt (data toEncrypt: Data) throws -> Data {
		do {
			let data: Data = try coreCipher.encrypt(data: toEncrypt)
			return data
		}
		catch let error {
			throw error
		}
	}
	
	public func decrypt(data toDecrypt: Data) throws -> Data {
		do {
			let data: Data = try coreCipher.decrypt(data: toDecrypt)
			return data
		}
		catch let error {
			throw error
		}
	}
}

public class AESBlockEncryption: NSObject {
	fileprivate let aesCipher: AESCipher
	
	init(aesCipher cipher: AESCipher) {
		aesCipher = cipher
		super.init()
	}
	
	public func update(withDataBlock data: Data) throws {
		do {
			try aesCipher.coreCipher.updateEncryption(data: data)
		}
		catch let error {
			throw error
		}
	}

	public func finish() throws -> Data {
		do {
			let finalData = try aesCipher.coreCipher.finishEncryption()
			return finalData
		}
		catch let error{
			throw error
		}
	}
}

class AESCoreCipher: NSObject {
	static let ivSize = 16
	fileprivate let key: Data?
	fileprivate let iv: Data?
	
	private let blockMode: AESBlockCipherMode?
	private var aesCipher: UnsafePointer<EVP_CIPHER>?
	private var context: UnsafeMutablePointer<EVP_CIPHER_CTX>?

	private var decContext: UnsafeMutablePointer<EVP_CIPHER_CTX>?

	
	init(key: Data, iv: Data, blockMode: AESBlockCipherMode) throws {
		self.key = key
		self.iv = iv
		self.blockMode = blockMode
		super.init()
		
		if isValid(cipherKey: key) == false { throw CipherGeneralError.invalidKey(reason: "AES Key must be of size: 16, 24 or 32 bytes") }
		decideAESCipher()
	}
	
	fileprivate func encrypt(data: Data) throws -> Data {
		
		do {
			try updateEncryption(data: data)
			let finalData = try finishEncryption()
			return finalData
		}
		catch {
			throw CipherGeneralError.cipherProcessFail(reason: "Encrypt Failed")
		}
	}
	
	fileprivate func updateEncryption(data toUpdate: Data) throws {
		if let key = key, let iv = iv {
			
			let dataPointer = UnsafeMutablePointer<UInt8>(mutating: (toUpdate as NSData).bytes.bindMemory(to: UInt8.self, capacity: toUpdate.count))
			
			if !isUpdateInProcess() {
				do {
					try initEncryption(withKey: key, andIV: iv)
				}
				catch let error {
					throw error
				}
			}
			
			if let ctx = context {
				var resultData = [UInt8](repeating: UInt8(), count: key.count)
				let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
				
				let updateCheck = EVP_EncryptUpdate(ctx, &resultData, resultSize, dataPointer, Int32(toUpdate.count))
				if updateCheck == 0 {
					throw CipherGeneralError.cipherProcessFail(reason: "Update Encryption UPDATE fail")
				}
			}
			
		}
		
	}

	fileprivate func initEncryption(withKey key: Data, andIV iv: Data) throws {
		self.context = EVP_CIPHER_CTX_new()
//		EVP_CIPHER_CTX_set_padding(self.context!, PKCS5)
		let keyPointer = UnsafeMutablePointer<UInt8>(mutating: (key as NSData).bytes.bindMemory(to: UInt8.self, capacity: key.count))
		let ivPointer = UnsafeMutablePointer<UInt8>(mutating: (iv as NSData).bytes.bindMemory(to: UInt8.self, capacity: iv.count))
		let initCheck = EVP_EncryptInit(context!, self.aesCipher, keyPointer, ivPointer)
		if initCheck == 0 {
			throw CipherGeneralError.cipherProcessFail(reason: "Update Encryption INIT fail")
		}
	}
	
	fileprivate func finishEncryption() throws -> Data {
		if let ctx = context, let key = key {
			var resultData = [UInt8](repeating: UInt8(), count: key.count)
			let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
			let finalCheck = EVP_EncryptFinal(ctx, &resultData, resultSize)
			if finalCheck == 0 {
				throw CipherGeneralError.cipherProcessFail(reason: "Encryption FINAL fail")
			}
			
			let result = Data(resultData)
			EVP_CIPHER_CTX_cleanup(self.context)
			self.context = nil
			return result
		}
		else {
			throw CipherGeneralError.cipherProcessFail(reason: "Encryption invalid or missing parameters")
		}
	}
	
	fileprivate func isUpdateInProcess() -> Bool {
		if let _  = context {return true}
		return false
	}
	
	fileprivate func decrypt(data: Data) throws -> Data {
	
		if let iv = self.iv, let key = self.key {
			do {
				try initDecryption(withKey: key, andIV: iv)
				try updateDecryption(withData: data)
				let finishData = try finishDecryption()
				return finishData
			}
			catch let error {
				throw error
			}
		}
		else {
			throw CipherGeneralError.cipherProcessFail(reason: "Decrypt AES No key or iv")
		}
	}
	
////		return Data()
//		let dataPointer = UnsafeMutablePointer<UInt8>(mutating: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count))
//		let ctx = EVP_CIPHER_CTX_new()
//		
//		let keyPointer = UnsafeMutablePointer<UInt8>(mutating: (key! as NSData).bytes.bindMemory(to: UInt8.self, capacity: key!.count))
//		let ivPointer = UnsafeMutablePointer<UInt8>(mutating: (iv! as NSData).bytes.bindMemory(to: UInt8.self, capacity: iv!.count))
//		
//		var resultData = [UInt8](repeating: UInt8(), count: 32)
//		let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
//		
//		EVP_DecryptInit(ctx, self.aesCipher, keyPointer, ivPointer)
//		EVP_DecryptUpdate(ctx, &resultData, resultSize, dataPointer, Int32(data.count))
////		EVP_DecryptUpdate(ctx, nil, nil, dataPointer, Int32(data.count))
//		EVP_DecryptFinal(ctx, &resultData, resultSize)
//		
//		return Data(resultData)
	
	fileprivate func initDecryption(withKey key: Data, andIV iv: Data) throws {
		
		self.decContext = EVP_CIPHER_CTX_new()
		
		let keyPointer = UnsafeMutablePointer<UInt8>(mutating: (key as NSData).bytes.bindMemory(to: UInt8.self, capacity: key.count))
		let ivPointer = UnsafeMutablePointer<UInt8>(mutating: (iv as NSData).bytes.bindMemory(to: UInt8.self, capacity: iv.count))
		
		let initStatus = EVP_DecryptInit(self.decContext!, self.aesCipher, keyPointer, ivPointer)
		if initStatus == 0 {
			throw CipherGeneralError.cipherProcessFail(reason: "AES Decryption status = 0")
		}
	}
	
	fileprivate var decryptionResultSize: Int32 = 0
	
	fileprivate func updateDecryption(withData data: Data) throws {
			let dataPointer = UnsafeMutablePointer<UInt8>(mutating: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count))

			var resultData = [UInt8](repeating: UInt8(), count: 32)
			let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
			
			if let ctx = self.decContext {
				let updateStatus = EVP_DecryptUpdate(ctx, &resultData, resultSize, dataPointer, Int32(data.count))
				decryptionResultSize += resultSize.pointee
				if updateStatus == 0 {
					throw CipherGeneralError.cipherProcessFail(reason: "AES Update Status = 0")
				}
			}
	}

	fileprivate func finishDecryption() throws -> Data {
		
		if let ctx = decContext {
			var resultData = [UInt8]()
			let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
			var finishStatus = EVP_DecryptFinal_ex(ctx, &resultData, resultSize) //EVP_DecryptFinal(ctx, &resultData, resultSize)
			
			if finishStatus == 1 {
				resultData = [UInt8](repeating: UInt8(), count: Int(resultSize.pointee))
				finishStatus = EVP_DecryptFinal_ex(ctx, &resultData, resultSize)
				
				if finishStatus == 0 {
					printCryptoError()
					throw CipherGeneralError.cipherProcessFail(reason: "AES Decrypt Status = 0")
				}
			}
			self.context = nil
			return Data(resultData)
		}
		else {
			throw CipherGeneralError.cipherProcessFail(reason: "AES Decrypt Fail")
		}
	}
	
	fileprivate func decideAESCipher() {
		if let keySize = key?.count, let bcm = blockMode {
			if AESKeySize.isAES128(keySize: keySize) && AESBlockCipherMode.isBlockModeCBC(blockMode: bcm) {
				aesCipher = EVP_aes_128_cbc()
			}
			else if AESKeySize.isAES128(keySize: keySize) && AESBlockCipherMode.isBlockModeECB(blockMode: bcm) {
				aesCipher = EVP_aes_128_ecb()
			}
			else if AESKeySize.isAES128(keySize: keySize) && AESBlockCipherMode.isBlockModeCFB(blockMode: bcm) {
				aesCipher = EVP_aes_128_cfb1()
			}
			else if AESKeySize.isAES128(keySize: keySize) && AESBlockCipherMode.isBlockModeOFB(blockMode: bcm) {
				aesCipher = EVP_aes_128_ofb()
			}
			else if AESKeySize.isAES128(keySize: keySize) && AESBlockCipherMode.isBlockModeCTR(blockMode: bcm) {
				aesCipher = EVP_aes_128_ctr()
			}
			else if AESKeySize.isAES256(keySize: keySize) && AESBlockCipherMode.isBlockModeCBC(blockMode: bcm) {
				aesCipher = EVP_aes_256_cbc()
			}
			else if AESKeySize.isAES256(keySize: keySize) && AESBlockCipherMode.isBlockModeECB(blockMode: bcm) {
				aesCipher = EVP_aes_256_ecb()
			}
			else if AESKeySize.isAES256(keySize: keySize) && AESBlockCipherMode.isBlockModeCFB(blockMode: bcm) {
				aesCipher = EVP_aes_256_cfb1()
			}
			else if AESKeySize.isAES256(keySize: keySize) && AESBlockCipherMode.isBlockModeOFB(blockMode: bcm) {
				aesCipher = EVP_aes_256_ofb()
			}
			else if AESKeySize.isAES256(keySize: keySize) && AESBlockCipherMode.isBlockModeCTR(blockMode: bcm) {
				aesCipher = EVP_aes_256_ctr()
			}
			else if AESKeySize.isAES192(keySize: keySize) && AESBlockCipherMode.isBlockModeCBC(blockMode: bcm) {
				aesCipher = EVP_aes_192_cbc()
			}
			else if AESKeySize.isAES192(keySize: keySize) && AESBlockCipherMode.isBlockModeECB(blockMode: bcm) {
				aesCipher = EVP_aes_192_ecb()
			}
			else if AESKeySize.isAES192(keySize: keySize) && AESBlockCipherMode.isBlockModeCFB(blockMode: bcm) {
				aesCipher = EVP_aes_192_cfb1()
			}
			else if AESKeySize.isAES192(keySize: keySize) && AESBlockCipherMode.isBlockModeOFB(blockMode: bcm) {
				aesCipher = EVP_aes_192_ofb()
			}
			else if AESKeySize.isAES192(keySize: keySize) && AESBlockCipherMode.isBlockModeCTR(blockMode: bcm) {
				aesCipher = EVP_aes_192_ctr()
			}
		}
	}
	
	fileprivate func isValid(cipherKey key: Data) -> Bool {
		if let _ = AESKeySize(rawValue: key.count) { return true}
		return false
	}
	
	fileprivate func printCryptoError(){
		ERR_load_CRYPTO_strings()
		let err = UnsafeMutablePointer<CChar>.allocate(capacity: 130)
		ERR_error_string(ERR_get_error(), err)
		print("ENC ERROR \(String(cString: err))")
		err.deinitialize()
		err.deallocate(capacity: 130)
	}
}
