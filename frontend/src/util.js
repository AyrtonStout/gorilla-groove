export function range(start, count) {
	return Array(count)
		.fill(0)
		.map((_, index) => { return index + start;});
}

// FIXME
// I had a feeling this wouldn't work that well, and it doesn't really. It could be made to work,
// but it's sure a hassle, and it's unlikely that the frontend will sort EXACTLY like the DB when
// it comes to things like special characters.

// Instead of doing this, I think I should have the backend return the index of the song after it
// gets inserted. That seems like it'd be a lot simpler. Wish I had thought of that before

// sortKeys is something like [{key: artist, dir: asc}, {key: album, dir: desc}]
export function findSpotInSortedArray(item, array, sortKeys) {
	// For each item in our sorted array
	for (let i = 0; i < array.length; i++) {
		// For each key in the objects that we are comparing
		for (let j = 0; j < sortKeys.length; j++) {
			let rawItemValue = item[sortKeys[j].key];
			let rawCompareValue = array[i][sortKeys[j].key];

			let itemValue = rawItemValue !== null ? rawItemValue.toString().toLowerCase() : '';
			let compareValue = rawCompareValue !== null ? rawCompareValue.toString().toLowerCase() : '';

			if (itemValue === compareValue) {
				// If the values are equal and this is the last thing to compare,
				// then they are equal and this is a valid sort location
				if (j === sortKeys.length - 1) {
					return i;
				} else {
					// Otherwise, continue and check the next key in our sort and see if they are still equal
					// Explicitly calling continue here just to map out all the branches in this if-else logic
					// noinspection UnnecessaryContinueJS
					continue;
				}
			} else {
				let sortDirection = sortKeys[j].dir;

				// If we are ascending, and our value is smaller than the next value, then we have found our spot
				if (sortDirection === 'asc' && itemValue < compareValue) {
					return i;
				} else if (sortDirection === 'desc' && itemValue > compareValue) {
					return i;
				} else {
					// We already know that the keys we're comparing aren't equal. So we don't have to check the next keys.
					// Our sort location lies further down the array
					break;
				}
			}
		}
	}

	// We made it through the entire array without sorting ourselves. So we must belong at the end of the array
	return array.length;
}

export function arrayIntersection(array1, array2) {
	return array1.filter(val => array2.includes(val));
}

export function arrayDifference(array1, array2) {
	return array1.filter(val => !array2.includes(val));
}

export function mapKeys(object, transformFunction) {
	let keys = Object.keys(object);
	let newObject = {};

	keys.forEach(key => {
		let newKey = transformFunction(key);
		newObject[newKey] = object[key]
	});

	return newObject;
}

// Pretty basic. Might be better if it checked that the token was valid, but that would require http call
export function isLoggedIn() {
	return document.cookie.indexOf('cookieToken') !== -1;
}

// https://stackoverflow.com/a/2117523
export function uuidv4() {
	return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, c =>
		(c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
	);
}
