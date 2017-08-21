/***
bigint.inc - Big Integers Operation Library Functions

Version: 0.1
Date: 28-12-2014
Author: Statik

Provides some arithmetic and logical math functions to operate 
with big integers.

**UNFINISHED**

***/

#if defined _BigInt_included
	#endinput
#endif

#define _BigInt_included

stock modpowBigInt(base[], exponent[], modulus[], nBase, output[], oSize) // http://en.wikipedia.org/wiki/Modular_exponentiation
{ // Modular exponentiation, Right-to-left binary method (binary exponentiation + memory efficient method)
	new eSize = getBigIntSize(exponent);
	new mSize = getBigIntSize(modulus);
	new auxSize = (mSize+1)*2; // output and base (pow base) are never bigger than modulus
	decl aux[auxSize];
	decl auxBase[auxSize]; // Is used as a replacemente of the power base, not the numeric base
	decl auxExponent[eSize+1];
	new parity[2];
	
	output[0] = 1;
	output[1] = -1;
	copyBigInt(base, auxBase, auxSize);
	copyBigInt(exponent, auxExponent, eSize+1);
	modBigInt(base, modulus, nBase, auxBase, auxSize);
	
	while (isBiggerThanBigNumber(auxExponent, {0,-1})) // exponent > 0
	{
		fulldivBigInt(auxExponent, {2,-1}, nBase, auxExponent, eSize+1, parity, sizeof(parity));
		if (parity[0] == 1) // (exponent % 2) == 1 / Is exponent odd?
		{
			multBigInt(output, auxBase, nBase, aux, auxSize);
			modBigInt(aux, modulus, nBase, output, oSize);
		}
		multBigInt(auxBase, auxBase, nBase, auxBase, auxSize);
		modBigInt(auxBase, modulus, nBase, auxBase, auxSize);
	}
}

stock powBigInt(number[], exponent[], base, output[], oSize) // Exponentiation by squaring recursive algorithm **UNFINISHED**
{ // http://en.wikipedia.org/wiki/Exponentiation_by_squaring
	new nSize = getBigIntSize(number);
	new eSize = getBigIntSize(exponent);
	if (!isBiggerThanBigNumber(exponent, {0,-1})) // Exponent is 0
	{
		output[0] = 1;
		output[1] = -1;
		return;
	}
	if (!isBiggerThanBigNumber(exponent, {1,-1})) // Exponent is 1
	{
		for (new i = 0; i <= nSize; i++)
		{
			output[i] = number[i];
		}
		return;
	}
	new bool:isExponentEven = (exponent[0] % 2) == 0;
	multBigInt(number, number, base, output, oSize); // number^2
	if (!isBiggerThanBigNumber(exponent, {2,-1})) return;
	
	if (isExponentEven)
	{
		//powBigInt(output, exponent/2, base, output, oSize);
	}
	else
	{
		
		//powBigInt(output, exponent-1/2, base, output, oSize);
	}
}

stock multBigInt(n1[], n2[], base, output[], oSize)
{
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	if (n1Size < 40000 && n2Size < 40000)
	{
		standardMult(n1, n2, base, output, oSize);
	}
	else
	{
		karatsubaMult(n1, n2, base, output, oSize);
	}
}

stock divBigInt(n1[], n2[], base, output[], oSize)
{
	new n2Size = getBigIntSize(n2);
	decl remainder[n2Size+1]; // Remainder is never bigger than divisor/denominator
	fulldivBigInt(n1, n2, base, output, oSize, remainder, n2Size+1);
}

stock modBigInt(n1[], n2[], base, output[], oSize)
{
	new n1Size = getBigIntSize(n1);
	decl quotient[n1Size+1]; // Quotient is never bigger than dividend/numerator
	fulldivBigInt(n1, n2, base, quotient, n1Size+1, output, oSize);
}

stock fulldivBigInt(n1[], n2[], base, quotient[], qSize, remainder[], rSize)
{
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	
	if (qSize < (n1Size+1)) return;
	if (!isBiggerThanBigNumber(n2, {0,-1})) // n2 == 0
		return;
	
	if (n2Size > n1Size)
	{
		quotient[0] = 0;
		quotient[1] = -1;
		copyBigInt(n1, remainder, rSize);
		return;
	}
	decl tempRemainder[rSize+1];
	tempRemainder[0] = -1;
	quotient[n1Size] = -1;
	new i;
	for (i = n1Size-1; i >= 0; i--)
	{
		leftShiftBigInt(tempRemainder, 1);
		trimBigInt(tempRemainder);
		tempRemainder[0] = n1[i];
		quotient[i] = 0;
		while (!isBiggerThanBigNumber(n2, tempRemainder)) // (tempRemainder >= n2)
		{
			subBigInt(tempRemainder, n2, base, tempRemainder, rSize);
			quotient[i]++;
		}
	}
	copyBigInt(tempRemainder, remainder, rSize);
	trimBigInt(quotient);
}

stock karatsubaMult(n1[], n2[], base, output[], oSize) // Karatsuba recursive algorithm
{	// http://en.wikipedia.org/wiki/Karatsuba_algorithm#Pseudo_Code_Implementation
	if (oSize < 2) return;
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	if (n1Size == 1 || n2Size == 1) // Base case 
	{
		standardMult(n1, n2, base, output, oSize);
		return;
	}
	new m = (n1Size > n2Size) ? n1Size : n2Size;
	new m2 = m/2;
	
	decl l1[oSize], h1[oSize];
	decl l2[oSize], h2[oSize];
	splitBigIntAt(n1, m2, l1, oSize, h1, oSize);
	splitBigIntAt(n2, m2, l2, oSize, h2, oSize);
	
	decl z0[oSize]; // <-
	karatsubaMult(l1, l2, base, z0, oSize);
	//standardMult(l1, l2, base, z0, oSize);
	
	decl z1[oSize]; // <-
	decl l1plush1[oSize];
	decl l2plush2[oSize];
	addBigInt(l1, h1, base, l1plush1, oSize);
	addBigInt(l2, h2, base, l2plush2, oSize);
	karatsubaMult(l1plush1, l2plush2, base, z1, oSize);
	//standardMult(l1plush1, l2plush2, base, z1, oSize);
	
	decl z2[oSize]; // <-
	karatsubaMult(h1, h2, base, z2, oSize);
	//standardMult(h1, h2, base, z2, oSize);
	
	decl z3[oSize]; // <-
	subBigInt(z1, z2, base, z3, oSize);
	subBigInt(z3, z0, base, z3, oSize);
	
	leftShiftBigInt(z2, 2*m2);
	leftShiftBigInt(z3, m2);
	
	addBigInt(z2, z3, base, output, oSize);
	addBigInt(output, z0, base, output, oSize);
	
	trimBigInt(output);
}

stock standardMult(n1[], n2[], base, output[], oSize)
{
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	new bool:n1b = isBiggerThanBigNumber(n1, n2); // Is n1 bigger
	new sSize = (n1b) ? n2Size : n1Size; // Smallest size
	new bSize = (n1b) ? n1Size : n2Size; // Biggest size
	new carry = 0;
	decl value[sSize][oSize];
	new temp, i, u;
	for (i = 0; i < sSize; i++)
	{
		for (u = 0; u < bSize; u++)
		{
			temp = n1[(n1b)?u:i] * n2[(n1b)?i:u] + carry;
			if (temp >= base)
			{
				carry = temp / base;
				value[i][u] = temp % base;
			}
			else
			{
				carry = 0;
				value[i][u] = temp;
			}
		}
		if (carry != 0)
		{
			value[i][u] = carry;
			value[i][u+1] = -1;
			carry = 0;
		}
		else 
		{
			value[i][u] = -1;
		}
		leftShiftBigInt(value[i], i);
	}
	output[0] = -1; // Initializes output
	for (i = 0; i < sSize; i++)
	{
		addBigInt(output, value[i], base, output, oSize);
	}
	trimBigInt(output);
}

stock addBigInt(n1[], n2[], base, output[], oSize) // Standard algorithm
{
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	new carry = 0;
	new temp;
	new i;
	for (i = 0; (i < n1Size || i < n2Size); i++)
	{
		if (i == oSize) return;
		if (i >= n1Size) temp = n2[i] + carry;
		else if (i >= n2Size) temp = n1[i] + carry;
		else temp = n1[i] + n2[i] + carry;
		
		if (temp >= base)
		{
			output[i] = temp - base;
			carry = 1;
		}
		else
		{
			output[i] = temp;
			carry = 0;
		}
	}
	if (carry == 1) // Adds the last carry
	{
		output[i] = carry;
		output[i+1] = -1;
	}
	else output[i] = -1;
	trimBigInt(output);
}

stock subBigInt(n1[], n2[], base, output[], oSize) // Standard algorithm
{
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	new carry = 0;
	new temp;
	new i;
	for (i = 0; (i < n1Size || i < n2Size); i++)
	{
		if (i == oSize) return;
		if (i >= n1Size) temp = n2[i] - carry;
		else if (i >= n2Size) temp = n1[i] - carry;
		else temp = n1[i] - n2[i] - carry;
		
		if (temp < 0)
		{
			output[i] =  temp + base;
			carry = 1;
		}
		else
		{
			output[i] = temp;
			carry = 0;
		}
	}
	output[i] = -1;
	trimBigInt(output);
}

stock bool:splitBigIntAt(number[], index, lowOut[], loSize, highOut[], hoSize)
{
	new nSize = getBigIntSize(number);
	if (index == 0) return false;
	if (index >= nSize) return false;
	if (index >= loSize) return false;
	if (nSize-index >= hoSize) return false;
	
	new i;
	for (i = 0; i < index; i++)
	{
		lowOut[i] = number[i];
	}
	lowOut[i] = -1;
	trimBigInt(lowOut);
	
	for (i = index; i < nSize; i++)
	{
		highOut[i-index] = number[i];
	}
	highOut[i-index] = -1;
	trimBigInt(highOut);
	
	return true;
}

stock bool:isEqualToBigNumber(n1[], n2[])
{
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	if (n1Size != n2Size) return false;
	
	for (new i = 0; i < n1Size; i++)
	{
		if (n1[i] != n2[i]) return false;
	}
	return true;
}

stock bool:isBiggerThanBigNumber(n1[], n2[])
{
	new n1Size = getBigIntSize(n1);
	new n2Size = getBigIntSize(n2);
	if (n1Size > n2Size) return true;
	if (n1Size < n2Size) return false;
	
	for (new i = (n1Size-1); i >= 0; i--)
	{
		if (n1[i] == n2[i]) continue;
		else if (n1[i] > n2[i]) return true;
		else return false;
	}
	return false; // In case both numbers are the same
}

stock leftShiftBigInt(number[], digits) // Logical shift
{
	if (digits == 0) return;
	new nSize = getBigIntSize(number);
	decl temp[nSize+1];
	for (new i = 0; i <= nSize; i++) // Creates a backup
	{
		temp[i] = number[i];
	}
	for (new a = 0; a < digits; a++) // Fills with zeros
	{
		number[a] = 0;
	}
	for (new i = 0; i <= nSize; i++) // Puts the backup back in
	{
		number[i+digits] = temp[i];
	}
	trimBigInt(number);
}

stock trimBigInt(number[]) // Removes left padded zeros
{
	new nSize = getBigIntSize(number);
	for (new zeros = 0; number[nSize-zeros-1] == 0; zeros++)
	{ 
		if (nSize-zeros-1 != 0) number[nSize-zeros-1] = -1;
	}
}

stock copyBigInt(number[], output[], oSize)
{
	new nSize = getBigIntSize(number);
	if (oSize <= nSize) return;
	for (new i = 0; i <= nSize; i++)
	{
		output[i] = number[i];
	}
}

stock getBigIntSize(number[])
{
	new i;
	for (i = 0; number[i] != -1; i++){}
	return i;
}

stock toBase256BigInt(number[], output[], oLength)
{
	new nSize = getBigIntSize(number);
	new finalLength = nSize/2 + (nSize%2);
	if (oLength < finalLength) return 0;
	new i;
	new high, low;
	
	for (i = 0; i < finalLength; i++)
	{
		if ((i == finalLength-1) && nSize%2 == 1)
			high = 0;
		else
			high = number[i*2+1];
		low = number[i*2];
		output[finalLength-i-1] = (high << 4) + low;
	}
	return finalLength;
}

stock bool:hexString2BigInt(const String:hexString[], output[], oSize)
{

	new i;
	new temp[oSize];
	for(i = 0; hexString[i] != 0; i++)
	{
		if (i >= oSize) return false;
		temp[i] = hexChar2Int(hexString[i]);
		
		if (temp[i] == -1) return false;
	}
	// Inverts number string
	for (new u = 0; u < i; u++)
	{
		output[u] = temp[i-u-1];
	}
	output[i] = -1; // Terminates the number string
	trimBigInt(output);
	return true;
}

stock bool:bigInt2HexString(input[], String:hexString[], hsSize)
{
	new nSize = getBigIntSize(input);
	new i;
	for (i = 0; i < (hsSize-1); i++)
	{
		if (i == nSize) break;
		if ((hexString[i] = int2HexChar(input[nSize-i-1])) == -1) return false;
	}
	hexString[i] = 0;
	return true;
	
}

stock hexChar2Int(input)
{
	if(input >= '0' && input <= '9')
		return input - '0';
	if(input >= 'A' && input <= 'F')
		return input - 'A' + 10;
	if(input >= 'a' && input <= 'f')
		return input - 'a' + 10;
	return -1;
}

stock int2HexChar(input)
{
	if (input >= 0 && input <= 9)
		return input + '0';
	if (input >= 10 && input <= 16)
		return input + 'A' - 10;
	return -1;	
}

/*
test()
{
	// LOTS OF TESTS
	PrintDebug(caller, "Modulus size: %i", getBigIntSize(modulus));
	
	/// Addition test
	new n1[] = {0xC,9,4,9,0xF,0,-1};
	new n2[] = {0,0x3,5,7,-1};
	decl String:s1[7];
	decl String:s2[7];
	bigInt2HexString(n1, s1, sizeof(s1));
	bigInt2HexString(n2, s2, sizeof(s2));
	PrintDebug(caller, "HEX 1 : %s", s1);
	PrintDebug(caller, "HEX 2 : %s", s2);
	new a[20];
	addBigInt(n1, n2, 16, a, sizeof(a));
	new String:sa[20];
	bigInt2HexString(a, sa, sizeof(sa));
	PrintDebug(caller, "HEX 1 + HEX 2 = %s", sa);
	
	/// Split test
	new n3[] = {4,6,8,2,5,7,3,4,7,2,-1};
	new n4[15];
	new n5[15];
	splitBigIntAt(n3, 5, n4, sizeof(n4), n5, sizeof(n5));
	new String:s3[30];
	new String:s4[15];
	new String:s5[15];
	bigInt2HexString(n3, s3, sizeof(s3));
	bigInt2HexString(n4, s4, sizeof(s4));
	bigInt2HexString(n5, s5, sizeof(s5));
	PrintDebug(caller, "%s splitted at index %i", s3, 5);
	PrintDebug(caller, "Low: %s", s4);
	PrintDebug(caller, "High: %s", s5);
	
	/// Subtraction test
	new n6[] = {3,1,3,5,5,9,6,9,-1};
	new n7[] = {1,3,5,6,9,6,9,2,-1};
	decl String:s6[10];
	decl String:s7[10];
	bigInt2HexString(n6, s6, sizeof(s6));
	bigInt2HexString(n7, s7, sizeof(s7));
	new n8[10];
	new String:s8[10];
	subBigInt(n6, n7, 16, n8, sizeof(n8));
	bigInt2HexString(n8, s8, sizeof(s8));
	PrintDebug(caller, "Subtracting %s to %s...", s7, s6);
	PrintDebug(caller, "Result: %s", s8);
	
	/// Shift test
	new n9[] = {3,7,9,1,5,7,8,1,-1};
	decl String:s9[15];
	bigInt2HexString(n9, s9, sizeof(s9));
	PrintDebug(caller, "Shifting %s 3 numbers to left", s9);
	leftShiftBigInt(n9, 3);
	bigInt2HexString(n9, s9, sizeof(s9));
	PrintDebug(caller, "Result: %s", s9);
	
	/// Standard multiplication test
	new n10[] = {3,1,3,5,5,9,6,9,-1};
	new n11[] = {1,3,5,6,9,6,9,2,-1};
	decl String:s10[10];
	decl String:s11[10];
	bigInt2HexString(n10, s10, sizeof(s10));
	bigInt2HexString(n11, s11, sizeof(s11));
	new n12[30];
	new String:s12[30];
	standardMult(n10, n11, 16, n12, sizeof(n12));
	bigInt2HexString(n12, s12, sizeof(s12));
	PrintDebug(caller, "Multiplying (standard) %s to %s...", s10, s11);
	PrintDebug(caller, "Result: %s", s12);
	
	/// Karatsuba multiplication test
	new n13[] = {3,1,3,5,5,9,6,9,-1};
	new n14[] = {1,3,5,6,9,6,9,2,-1};
	decl String:s13[10];
	decl String:s14[10];
	bigInt2HexString(n13, s13, sizeof(s13));
	bigInt2HexString(n14, s14, sizeof(s14));
	new n15[30];
	new String:s15[30];
	karatsubaMult(n13, n14, 16, n15, sizeof(n15));
	bigInt2HexString(n15, s15, sizeof(s15));
	PrintDebug(caller, "Multiplying (karatsuba) %s to %s...", s13, s14);
	PrintDebug(caller, "Result: %s", s15);
	
	/// Exponentiation test
	new n16[] = {3,4,5,6,2,5,-1};
	new n17[] = {0,1,-1};
	decl String:s16[20];
	decl String:s17[20];
	bigInt2HexString(n16, s16, sizeof(s16));
	bigInt2HexString(n17, s17, sizeof(s17));
	new n18[30];
	new String:s18[30];
	powBigInt(n16, n17, 16, n18, sizeof(n18));
	bigInt2HexString(n18, s18, sizeof(s18));
	PrintDebug(caller, "Exponentiating %s to %s...", s16, s17);
	PrintDebug(caller, "Result: %s", s18);
	
	/// Division test
	new n19[] = {9,0xC,7,2,-1};
	new n20[] = {6,2,6,-1};
	decl String:s19[20];
	decl String:s20[20];
	bigInt2HexString(n19, s19, sizeof(s19));
	bigInt2HexString(n20, s20, sizeof(s20));
	new n21[30];
	new String:s21[30];
	new n22[30];
	new String:s22[30];
	fulldivBigInt(n19, n20, 16, n21, sizeof(n21), n22, sizeof(n22));
	bigInt2HexString(n21, s21, sizeof(s21));
	bigInt2HexString(n22, s22, sizeof(s22));
	PrintDebug(caller, "Dividing %s to %s...", s19, s20);
	PrintDebug(caller, "Quotient: %s - Remainder: %s", s21, s22);
	
	/// PKCS#1 v1.5 Padding Scheme test
	//decl String:aux[1024] = "BE629EA2D835880BF2572379CC751C5FA44F4A09B6F8CE5CB52C53EEDD0314E77AC827219E78DB1473BBA7BBE8BABC85C02CBC308B75375AE7C4B3AA31A491BB08D1946328F2B1BCE3E07E96D1CFF5E95A553C083A424CD5F6B7F2B55F89B958F0AE3B80A94CF5FEB3BD9417ABD09E1A42456E99128169CCEC176FDF7D2893A5";
	new k = strlen(hexModulus);
	new String:paddedMessage[k+1];
	pkcs1v15Pad(message, k, paddedMessage, k+1);
	PrintDebug(caller, "Padding message: %s with %i length modulus ", message, k);
	PrintDebug(caller, "Result: %i - %s", strlen(paddedMessage), paddedMessage);
	
	/// Modular exponentiation test

	decl n23[1024];
	decl n24[20];
	decl n25[1024];
	hexString2BigInt(paddedMessage, n23, 1024);
	hexString2BigInt(hexExponent, n24, 20);
	hexString2BigInt(hexModulus, n25, 1024);

	//new n23[] = {3,2,-1};
	//new n24[] = {5,-1};
	//new n25[] = {6,2,6,-1};
	new String:s23[1024];
	new String:s24[40];
	new String:s25[1024];
	new n26[1024];
	new String:s26[1024];
	modpowBigInt(n23, n24, n25, 16, n26, sizeof(n26));
	bigInt2HexString(n23, s23, sizeof(s23));
	bigInt2HexString(n24, s24, sizeof(s24));
	bigInt2HexString(n25, s25, sizeof(s25));
	bigInt2HexString(n26, s26, sizeof(s26));
	PrintDebug(caller, "Modular Power Test");
	PrintDebug(caller, "base = %s", s23);
	PrintDebug(caller, "exponent = %s", s24);
	PrintDebug(caller, "modulus = %s", s25);
	PrintDebug(caller, "Result size: %i, result = \n%s", getBigIntSize(n26), s26);
}
*/