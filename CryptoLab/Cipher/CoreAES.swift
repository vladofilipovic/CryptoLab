//
//  CoreAES.swift
//  CryptoLab
//
//  Created by Branko Popovic on 4/26/17.
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
/**
Block modes for AES Cipher
*/
public enum AESBlockCipherMode {
	case cbc
	case ecb
	case cfb
	case ofb //dont reuse iv
	case ctr //dont reuse iv
	
	static func isBlockModeCBC(blockMode: AESBlockCipherMode) -> Bool {
		return .cbc == blockMode
	}
	static func isBlockModeECB(blockMode: AESBlockCipherMode) -> Bool {
		return .ecb == blockMode
	}
	static func isBlockModeCFB(blockMode: AESBlockCipherMode) -> Bool {
		return .cfb == blockMode
	}
	static func isBlockModeOFB(blockMode: AESBlockCipherMode) -> Bool {
		return .ofb == blockMode
	}
	static func isBlockModeCTR(blockMode: AESBlockCipherMode) -> Bool {
		return .ctr == blockMode
	}
}

class AESCoreCipher: NSObject, CoreBlockCryptor {
	static let ivSize = 16
	let key: Data?
	let iv: Data?
	
	private let blockMode: AESBlockCipherMode?
	private var aesCipher: UnsafePointer<EVP_CIPHER>?
	private var context: UnsafeMutablePointer<EVP_CIPHER_CTX>?
	
	private var decContext: UnsafeMutablePointer<EVP_CIPHER_CTX>?
	
	
	init(key: Data, iv: Data, blockMode: AESBlockCipherMode) throws {
		self.key = key
		self.iv = iv
		self.blockMode = blockMode
		super.init()
		
		if isValid(cipherKey: key) == false { throw CipherError.invalidKey(reason: "AES Key must be of size: 16, 24 or 32 bytes") }
		decideAESCipher()
	}
	
	func encrypt(data toEncrypt: Data) throws -> Data {
		
		do {
			try updateEncryption(data: toEncrypt)
			let finalData = try finishEncryption()
			return finalData
		}
		catch {
			throw  CipherError.cipherProcessFail(reason: CipherErrorReason.cipherEncryption)
		}
	}
	
	var currentEncryptedData: Data = Data()
	
	func updateEncryption(data toUpdate: Data) throws {
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
				var resultData = [UInt8](repeating: UInt8(), count: toUpdate.count)
				let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
				
				let updateCheck = EVP_EncryptUpdate(ctx, &resultData, resultSize, dataPointer, Int32(toUpdate.count))
				
				if updateCheck == 0 {
					throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherUpdate)
				}
				
				currentEncryptedData.append(Data(bytes: resultData))
			}
			
		}
		
	}
	
	func initEncryption(withKey key: Data, andIV iv: Data) throws {
		self.context = EVP_CIPHER_CTX_new()
		let keyPointer = UnsafeMutablePointer<UInt8>(mutating: (key as NSData).bytes.bindMemory(to: UInt8.self, capacity: key.count))
		let ivPointer = UnsafeMutablePointer<UInt8>(mutating: (iv as NSData).bytes.bindMemory(to: UInt8.self, capacity: iv.count))
		//let initCheck = EVP_EncryptInit(context!, self.aesCipher, keyPointer, ivPointer)
		let initCheck = EVP_EncryptInit_ex(context!, self.aesCipher, nil, keyPointer, ivPointer)
		if initCheck == 0 {
			throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherUpdate)
		}
	}
	
	func finishEncryption() throws -> Data {
		if let ctx = context {
			var resultData = [UInt8](repeating: UInt8(), count: 16) //(key?.count)!)
			let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
			let finalCheck = EVP_EncryptFinal_ex(ctx, &resultData, resultSize)
			
			if finalCheck == 0 {
				throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherFinish)
			}
			
			let result = Data(resultData)
			/*EVP_CIPHER_CTX_cleanup(self.context)
			self.context = nil*/
			if isNullData(data: currentEncryptedData) {
				return result
			}
			
			return currentEncryptedData //result //
		}
		else {
			throw CipherError.cipherProcessFail(reason: "AES Encryption invalid or missing parameters")
		}
	}
	
	fileprivate func isUpdateInProcess() -> Bool {
		if let _  = context {return true}
		return false
	}
	
	//MARK: Decryption
	
	var currentDecryptedData = Data()
	
	func decrypt(data toDecrypt: Data) throws -> Data {
		
		if let iv = self.iv, let key = self.key {
			do {
				try initDecryption(withKey: key, andIV: iv)
				try updateDecryption(withData: toDecrypt)
				let finishData = try finishDecryption()
				return finishData
			}
			catch let error {
				throw error
			}
		}
		else {
			throw CipherError.cipherProcessFail(reason: "AES Decrypt no key or iv")
		}
	}
	
	func initDecryption(withKey key: Data, andIV iv: Data) throws {
		
		self.decContext = EVP_CIPHER_CTX_new()
		let keyPointer = UnsafeMutablePointer<UInt8>(mutating: (key as NSData).bytes.bindMemory(to: UInt8.self, capacity: key.count))
		let ivPointer = UnsafeMutablePointer<UInt8>(mutating: (iv as NSData).bytes.bindMemory(to: UInt8.self, capacity: iv.count))
		
		let initStatus = EVP_DecryptInit(self.decContext!, self.aesCipher, keyPointer, ivPointer)
		if initStatus == 0 {
			throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherInit)
		}
	}
	
	fileprivate var decryptionResultSize: Int32 = 0
	
	func updateDecryption(withData data: Data) throws {
		let dataPointer = UnsafeMutablePointer<UInt8>(mutating: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count))
		
		var resultData = [UInt8](repeating: UInt8(), count: data.count)
		let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
		
		if let ctx = self.decContext {
			let updateStatus = EVP_DecryptUpdate(ctx, &resultData, resultSize, dataPointer, Int32(data.count))
			decryptionResultSize += resultSize.pointee
			if updateStatus == 0 {
				throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherUpdate)
			}
			
			currentDecryptedData.append(Data(bytes: resultData))
		}
	}
	
	func finishDecryption() throws -> Data {
		
		if let ctx = decContext {
			var resultData = [UInt8](repeating: UInt8(), count: Int(32)) //[UInt8]()
			let resultSize = UnsafeMutablePointer<Int32>.allocate(capacity: MemoryLayout<Int32.Stride>.size)
			var finishStatus = EVP_DecryptFinal_ex(ctx, &resultData, resultSize) //EVP_DecryptFinal(ctx, &resultData, resultSize)
			
			if finishStatus == 1 {
				resultData = [UInt8](repeating: UInt8(), count: Int(resultSize.pointee))
				finishStatus = EVP_DecryptFinal_ex(ctx, &resultData, resultSize)
				
				if finishStatus == 0 {
					throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherFinish)
				}
				
				if isNullData(data: currentDecryptedData) || (resultSize.pointee > 0  && currentDecryptedData.count != Int(resultSize.pointee)) {
					return Data(resultData)
				}
				self.decContext = nil
				return currentDecryptedData //Data(resultData)
			}
			else {
				throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherFinish)
			}
		}
		else {
			throw CipherError.cipherProcessFail(reason: CipherErrorReason.cipherFinish)
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
				aesCipher = EVP_aes_128_cfb128()
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
				aesCipher = EVP_aes_256_cfb128()
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
				aesCipher = EVP_aes_192_cfb128()
			}
			else if AESKeySize.isAES192(keySize: keySize) && AESBlockCipherMode.isBlockModeOFB(blockMode: bcm) {
				aesCipher = EVP_aes_192_ofb()
			}
			else if AESKeySize.isAES192(keySize: keySize) && AESBlockCipherMode.isBlockModeCTR(blockMode: bcm) {
				aesCipher = EVP_aes_192_ctr()
			}
		}
	}
	
	fileprivate func isNullData(data: Data) -> Bool {
		let nullStr = String(repeatElement("0", count: data.count * 2))
		return nullStr == data.hexEncodedString()
	}
	
	fileprivate func isValid(cipherKey key: Data) -> Bool {
		if let _ = AESKeySize(rawValue: key.count) { return true}
		return false
	}
}
