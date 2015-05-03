/***
rsa.inc - RSA Encrypting Algorithms Library Functions

Version: 0.1
Date: 28-03-2015
Author: Statik

Provides RSA PKCS #1 v1.5 encrypting functions.

**UNFINISHED**

***/

#if defined _RSA_included
	#endinput
#endif

#define _RSA_included

rsaEncrypt(const String:hexModulus[], const String:hexExponent[], const String:message[], String:ciphertext[], ctSize)
{
	decl modulus[1024];
	decl exponent[16];
	
	if (!hexString2BigInt(hexModulus, modulus, sizeof(modulus)))
	{
		PrintDebug(GetCaller(), "Error encrypting passphrase: Invalid modulus.");
		return;
	}
	
	if (!hexString2BigInt(hexExponent, exponent, sizeof(exponent)))
	{
		PrintDebug(GetCaller(), "Error encrypting passphrase: Invalid exponent.");
		return;
	}

	new k = strlen(hexModulus);
	new mSize = k + 1;
	if (ctSize < mSize) 
	{
		PrintDebug(GetCaller(), "Error encrypting passphrase: ciphertext size is can't be smaller than modulus size");
		
	}
	decl String:paddedMessage[mSize];
	pkcs1v15Pad(message, k, paddedMessage, mSize);
	PrintDebug(GetCaller(), "Padded message with PKCS#1 v1.5 standard (%i): \n%s", strlen(paddedMessage), paddedMessage);
	
	decl numericMessage[mSize];
	hexString2BigInt(paddedMessage, numericMessage, mSize);	
	
	decl encryptedMessage[mSize];
	modpowBigInt(numericMessage, exponent, modulus, 16, encryptedMessage, mSize);
	bigInt2HexString(encryptedMessage, ciphertext, ctSize);
}

pkcs1v15Pad(const String:data[], k, String:message[], maxSize) // Message must be even
{
	new dSize = strlen(data);
	new psSize = k - (dSize*2) - 6; // Padding string Size
	decl String:ps[psSize+1]; // Padding string / 1 more to add the string delimiter
	decl String:ds[(dSize*2)+1]; // Data string
	new i;
	for (i = 0; i < psSize; i++)
	{
		if ((i % 2) == 0) ps[i] = int2HexChar(GetRandomInt(1,15));
		else ps[i] = int2HexChar(GetRandomInt(0,15));
	}
	ps[i] = 0;
	for (i = 0; i < dSize; i++)
	{
		ds[i*2] =  int2HexChar(data[i] / 16); // High nibble 
		ds[i*2+1] = int2HexChar(data[i] % 16); // Low nibble
	}
	ds[i*2] = 0;
	
	Format(message, maxSize, "0002%s00%s", ps, ds);
}

encodeBase64(input[], paddingSize, String:output[], oSize)
{
	static const String:base64Table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	
	new iSize = getBigIntSize(input);
	if (paddingSize < iSize) return 0;
	new zeros = paddingSize - iSize;
	for (new e = 0; e < zeros; e++) { input[iSize++] = 0; }
	new finalSize = (iSize / 6) * 4;
	if (oSize < finalSize) return 0;
	
	new bitString = 0, u = 0, i;
	for (i = iSize-1; i >= 0; i-=3)
	{
		if (i == 1)
		{
			if (((iSize/3)%2) == 1) bitString = (input[i--] << 8) + (input[i--]);
			else  bitString = (input[i--] << 8) + (input[i--] << 4);
		}
		else if (i == 0)
		{
			if (((iSize/3)%2) == 1) bitString = input[i--] << 8;
			else  bitString = input[i--] << 4;
		}
		else bitString = (input[i] << 8) + (input[i-1] << 4) + (input[i-2]);
		
		output[u++] = base64Table[(bitString & 0b111111_000000)>>6];
		output[u++] = base64Table[bitString & 0b000000_111111];
	}
	
	for (new a = 0; a < (u%4); a++)
	{
		output[u++] = '=';
	}
	output[u++] = 0;
	return u;
}