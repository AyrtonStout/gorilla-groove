import React, {useEffect, useRef, useState} from 'react';
import {getScreenDimensions} from "../../util";

export default function PopoutMenu(props) {
	const [expanded, setExpanded] = useState(false);
	const [overrideCoordinates, setOverrideCoordinates] = useState(null);

	const mainItem = useRef(null);
	const childrenContainer = useRef(null);

	const closeMenu = () => {
		setExpanded(false);
	};

	const toggleExpanded = event => {
		event.stopPropagation();

		// Clicking on an item that is expandable on hover shouldn't actually do anything as it's just a grouping item
		if (!props.expansionOnHover && event.button !== 2) {
			setExpanded(!expanded);
		}
	};

	const setFromHover = newState => {
		if (props.expansionOnHover) {
			if (newState) {
				const { x, y, width: parentWidth } = mainItem.current.getBoundingClientRect();
				const { height, width } = childrenContainer.current.getBoundingClientRect();
				const { screenWidth, screenHeight } = getScreenDimensions();

				// Do some adjustments to the height to keep the popout menu in the screen as best as we can
				let newY = y;
				if (y + height > screenHeight) {
					newY = screenHeight - height;

					if (newY < 0) {
						newY = 0;
					}
				}

				let newX = x + parentWidth + 5;
				if (newX + width > screenWidth) {
					newX = x - 5 - width;
				}

				setOverrideCoordinates({ left: newX, top: newY });
			}
			setExpanded(newState);
		}
	};

	const getCustomStyle = () => {
		return overrideCoordinates === null ? {} : overrideCoordinates;
	};

	useEffect(() => {
		// If something using this view has its own view on how to handle expansion, don't handle it internally here
		if (props.expansionOverride !== undefined) {
			return;
		}

		if (expanded) {
			document.body.addEventListener('click', closeMenu);
		} else {
			document.body.removeEventListener('click', closeMenu);
		}
	}, [expanded]);

	let menuClass = props.expansionOverride || expanded ? '' : 'hidden';
	let mainItemClass = props.mainItem && props.mainItem.className ? props.mainItem.className : '';

	return (
		<div
			onMouseEnter={() => setFromHover(true)}
			onMouseLeave={() => setFromHover(false)}
		>
			{ props.mainItem ?
				<div
					ref={mainItem}
					className={`${mainItemClass} ${props.expansionOnHover ? 'expandable-width' : ''} p-relative`}
					onClick={toggleExpanded}
				>
					{props.mainItem.text}
					{ props.expansionOnHover ? <div className="expansion-caret">▶</div> : null }
				</div> : null
			}

			<div ref={childrenContainer} className={`popout-menu ${menuClass}`} style={getCustomStyle()}>
				<ul>
					{props.menuItems
						.filter(menuItem => menuItem.shouldRender === undefined || menuItem.shouldRender === true)
						.map((menuItem, index) => {
							if (menuItem.component) {
								return <li key={index}>{menuItem.component}</li>
							} else {
								return <li key={index} onClick={menuItem.clickHandler}>
									<span>{menuItem.text}</span>
								</li>
							}
						})}
				</ul>
			</div>
		</div>
	)
}
